import Foundation
import HealthKit
import MapKit
import UIKit
import CoreLocation

// MARK: - HealthKit Importer

actor HealthKitImporter {
    private let store = HKHealthStore()
    private var workoutCache: [String: HKWorkout] = [:]

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let ids: [HKQuantityTypeIdentifier] = [.heartRate, .distanceWalkingRunning, .activeEnergyBurned]
        types.formUnion(ids.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        return types
    }

    // MARK: Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            return true
        } catch { return false }
    }

    // MARK: Fetch

    /// HK에서 최근 100개 운동 조회 → `excluding`에 없는 것만 WorkoutLog로 변환
    func fetchNewWorkouts(excluding knownUUIDs: Set<String>) async -> [WorkoutLog] {
        let predicate = HKQuery.predicateForWorkouts(with: .greaterThanOrEqualTo, duration: 60)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]

        let hkWorkouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 100,
                sortDescriptors: sort
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        let newWorkouts = hkWorkouts.filter { !knownUUIDs.contains($0.uuid.uuidString) }
        var logs: [WorkoutLog] = []
        for workout in newWorkouts {
            workoutCache[workout.uuid.uuidString] = workout
            let hr = await fetchAverageHeartRate(for: workout)
            logs.append(WorkoutLog(
                hkUUID: workout.uuid.uuidString,
                source: .healthkit,
                activityType: WorkoutActivityType(hkType: workout.workoutActivityType),
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                durationSeconds: Int(workout.duration),
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                avgHeartRate: hr
            ))
        }
        return logs
    }

    func cachedWorkout(for hkUUID: String) -> HKWorkout? { workoutCache[hkUUID] }

    // MARK: Heart Rate

    private func fetchAverageHeartRate(for workout: HKWorkout) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate, options: .strictStartDate
        )
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                ))
            }
            store.execute(q)
        }
    }

    // MARK: Route Image

    /// GPS 경로가 있는 운동에 대해 지도 이미지 렌더 → JPEG Data 반환
    func renderRouteImage(for workout: HKWorkout) async -> Data? {
        guard let locations = await fetchRouteLocations(for: workout), locations.count > 5 else { return nil }
        return await renderMap(locations: locations)
    }

    private func fetchRouteLocations(for workout: HKWorkout) async -> [CLLocation]? {
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { cont in
            let sampleQuery = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: routePredicate,
                limit: 1,
                sortDescriptors: nil
            ) { [store] _, samples, _ in
                guard let route = samples?.first as? HKWorkoutRoute else {
                    cont.resume(returning: nil)
                    return
                }
                // HealthKit calls this closure serially on its own queue.
                // @unchecked Sendable lets us accumulate batches safely.
                final class LocationBatch: @unchecked Sendable { var items: [CLLocation] = [] }
                let batch = LocationBatch()
                let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if error != nil { cont.resume(returning: nil); return }
                    if let locations { batch.items.append(contentsOf: locations) }
                    if done { cont.resume(returning: batch.items.isEmpty ? nil : batch.items) }
                }
                store.execute(routeQuery)
            }
            store.execute(sampleQuery)
        }
    }

    // UIGraphicsImageRenderer, MKMapSnapshotter 모두 non-main thread에서 안전
    private func renderMap(locations: [CLLocation]) async -> Data? {
        let coords = locations.map(\.coordinate)
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }

        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  (maxLat - minLat) * 1.35,
            longitudeDelta: (maxLng - minLng) * 1.35
        )
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size   = CGSize(width: 600, height: 300)
        options.scale  = 2

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: options.size)
        let image = renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            var first = true
            for coord in coords {
                let pt = snapshot.point(for: coord)
                if first { path.move(to: pt); first = false }
                else      { path.addLine(to: pt) }
            }
            UIColor.systemOrange.withAlphaComponent(0.9).setStroke()
            path.lineWidth      = 3.5
            path.lineCapStyle   = .round
            path.lineJoinStyle  = .round
            path.stroke()

            // 시작점 초록 dot / 종료점 빨간 dot
            if let first = coords.first {
                let pt = snapshot.point(for: first)
                UIColor.systemGreen.setFill()
                UIBezierPath(ovalIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)).fill()
            }
            if let last = coords.last {
                let pt = snapshot.point(for: last)
                UIColor.systemRed.setFill()
                UIBezierPath(ovalIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)).fill()
            }
        }
        return image.jpegData(compressionQuality: 0.82)
    }
}
