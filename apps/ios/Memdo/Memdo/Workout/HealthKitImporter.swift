import Foundation
import HealthKit
import MapKit
import UIKit
import CoreLocation
import os

// MARK: - HealthKit Importer

actor HealthKitImporter {
    private let store = HKHealthStore()
    private var workoutCache: [String: HKWorkout] = [:]
    private static let logger = Logger(subsystem: "com.memdo.ios", category: "healthkit")
    private static let anchorDefaultsKey = "memdo.v1.healthKitWorkoutAnchor"

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
        } catch {
            // HealthKit deliberately doesn't reveal grant vs. deny for read-only
            // types via this call -- a caught error here is something else (no
            // entitlement, simulator without Health data, etc.), worth knowing
            // about when reports of "HealthKit won't connect" come in.
            Self.logger.error("HealthKit authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Fetch

    /// HK에서 마지막 체크포인트 이후 새 운동 조회 → `excluding`에 없는 것만 WorkoutLog로 변환.
    /// Returns the query's new anchor alongside the logs -- pass it to
    /// commitFetchProgress(_:) only once every returned log has actually
    /// been consumed (locally upserted). A caller that's only peeking
    /// (fetchPendingFromHealthKit, which doesn't save anything) must never
    /// commit, or a workout the user saw but declined to import would
    /// never be offered again -- HKAnchoredObjectQuery only returns a
    /// given sample once per anchor advance.
    func fetchNewWorkouts(excluding knownUUIDs: Set<String>) async -> (logs: [WorkoutLog], anchor: HKQueryAnchor?) {
        let predicate = HKQuery.predicateForWorkouts(with: .greaterThanOrEqualTo, duration: 60)

        // HKAnchoredObjectQuery narrows HealthKit's own scan to samples
        // added/changed since the last committed checkpoint, instead of
        // re-pulling and client-side-filtering the last 100 workouts on
        // every call regardless of how many were already seen -- for a
        // long-time user, most calls in steady state now have nothing new
        // to scan at all.
        let (hkWorkouts, newAnchor): ([HKWorkout], HKQueryAnchor?) = await withCheckedContinuation { cont in
            let q = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: loadAnchor(),
                limit: 100
            ) { _, samples, _, resultAnchor, _ in
                cont.resume(returning: ((samples as? [HKWorkout]) ?? [], resultAnchor))
            }
            store.execute(q)
        }

        // HKAnchoredObjectQuery has no sortDescriptors parameter (unlike
        // HKSampleQuery) -- sort here to keep the existing most-recent-
        // first ordering.
        let newWorkouts = hkWorkouts
            .sorted { $0.startDate > $1.startDate }
            .filter { !knownUUIDs.contains($0.uuid.uuidString) }
        for workout in newWorkouts {
            workoutCache[workout.uuid.uuidString] = workout
        }

        // Each fetchAverageHeartRate is its own independent HKStatisticsQuery
        // round trip -- awaiting them one at a time inside a loop sat on
        // HealthKitImportSheet's loading spinner for N sequential round
        // trips (20-50+ on a first connect, or after any gap) instead of
        // one batch. Run concurrently and reassemble by original index
        // (startDate-descending, from the query above) since TaskGroup
        // child completion order isn't guaranteed to match submission order.
        var heartRates = [Double?](repeating: nil, count: newWorkouts.count)
        await withTaskGroup(of: (Int, Double?).self) { group in
            for (index, workout) in newWorkouts.enumerated() {
                group.addTask { (index, await self.fetchAverageHeartRate(for: workout)) }
            }
            for await (index, hr) in group {
                heartRates[index] = hr
            }
        }

        let logs = newWorkouts.enumerated().map { index, workout in
            WorkoutLog(
                hkUUID: workout.uuid.uuidString,
                source: .healthkit,
                activityType: WorkoutActivityType(hkType: workout.workoutActivityType),
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                durationSeconds: Int(workout.duration),
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                avgHeartRate: heartRates[index]
            )
        }
        return (logs, newAnchor)
    }

    /// Commits the checkpoint from a fetchNewWorkouts(_:) call. Only the
    /// auto-import path (WorkoutModel.syncHealthKit) calls this, and only
    /// after its per-log processing loop has fully finished -- not right
    /// after the query returns -- so a mid-loop cancellation (backgrounding,
    /// termination) leaves the checkpoint uncommitted and the next sync
    /// naturally retries the same items instead of silently losing them.
    func commitFetchProgress(_ anchor: HKQueryAnchor?) {
        persistAnchor(anchor)
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorDefaultsKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func persistAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        else {
            UserDefaults.standard.removeObject(forKey: Self.anchorDefaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.anchorDefaultsKey)
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

        guard let route: HKWorkoutRoute = await withCheckedContinuation({ cont in
            let q = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: routePredicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkoutRoute)
            }
            store.execute(q)
        }) else { return nil }

        // Bridge HealthKit's serial callback into AsyncStream so accumulation
        // happens in the actor context, avoiding captured-var concurrency warnings.
        let stream = AsyncStream<[CLLocation]> { [store] continuation in
            let q = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if error != nil { continuation.finish(); return }
                if let locations { continuation.yield(locations) }
                if done { continuation.finish() }
            }
            store.execute(q)
        }

        var all: [CLLocation] = []
        for await batch in stream { all.append(contentsOf: batch) }
        return all.isEmpty ? nil : all
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
