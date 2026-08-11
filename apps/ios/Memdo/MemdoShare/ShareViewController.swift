import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        Task { await setup() }
    }

    private func setup() async {
        let text = await extractText()
        let shareView = ShareWorkoutView(
            initialNotes: text,
            onSave: { [weak self] workout in
                PendingWorkoutStore.enqueue(workout)
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )
        let host = UIHostingController(rootView: shareView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func extractText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }
        var parts: [String] = []

        for item in items {
            for provider in (item.attachments ?? []) {
                // URL (Nike Run Club, Strava 등)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let data = await loadData(provider, typeID: UTType.url.identifier),
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    parts.append(url.absoluteString)
                }
                // 텍스트 요약
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let data = await loadData(provider, typeID: UTType.plainText.identifier),
                   let text = String(data: data, encoding: .utf8) {
                    parts.append(text)
                }
            }
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadData(_ provider: NSItemProvider, typeID: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
