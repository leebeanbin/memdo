import SwiftUI
import UIKit

/// Keeps Agent in the native tab-bar position while treating it as an action.
/// SwiftUI exposes neither a tab-item frame nor a button-style tab, so this
/// narrow bridge measures and intercepts only the existing Agent tab item.
@MainActor
struct AgentTabBridge: UIViewRepresentable {
    @Binding var targetFrame: CGRect
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(targetFrame: $targetFrame, onTap: onTap)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.targetFrame = $targetFrame
        context.coordinator.onTap = onTap
        view.scheduleUpdate()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        coordinator.removeOverlay()
    }

    @MainActor
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleUpdate()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleUpdate()
        }

        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                coordinator?.installOverlay(relativeTo: self)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var targetFrame: Binding<CGRect>
        var onTap: () -> Void
        private weak var tabButton: UIView?
        private weak var tabBar: UITabBar?
        private let overlay = AgentHitControl()

        init(targetFrame: Binding<CGRect>, onTap: @escaping () -> Void) {
            self.targetFrame = targetFrame
            self.onTap = onTap
            super.init()
            overlay.backgroundColor = .clear
            overlay.isAccessibilityElement = true
            overlay.accessibilityLabel = "Memdo Agent 열기"
            overlay.accessibilityTraits = .button
            overlay.addTarget(self, action: #selector(pressed), for: .touchDown)
            overlay.addTarget(self, action: #selector(cancelled), for: [.touchCancel, .touchDragExit])
            overlay.addTarget(self, action: #selector(activated), for: .touchUpInside)
        }

        func installOverlay(relativeTo probe: UIView) {
            guard let window = probe.window,
                  let tabBar = findTabBar(in: window)
            else { return }
            self.tabBar = tabBar

            let resolved: CGRect
            if let agentButton = tabButtons(in: tabBar).last {
                if overlay.superview !== tabBar {
                    overlay.removeFromSuperview()
                    tabBar.addSubview(overlay)
                }
                tabButton?.accessibilityElementsHidden = false
                tabButton = agentButton
                agentButton.accessibilityElementsHidden = true
                overlay.targetView = agentButton
                overlay.frame = tabBar.bounds
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                overlay.accessibilityFrame = agentButton.convert(agentButton.bounds, to: nil)
                tabBar.bringSubviewToFront(overlay)
                resolved = agentButton.convert(agentButton.bounds, to: probe)
            } else {
                // Newer tab bars don't always expose per-item UIControls. Estimate
                // the trailing item's slice from the bar itself so the coach mark
                // still lands on Agent; taps keep working through the regular tab
                // selection binding in AppShellView.
                let itemCount = max(tabBar.items?.count ?? AppTab.allCases.count, 1)
                let itemWidth = tabBar.bounds.width / CGFloat(itemCount)
                let slice = CGRect(
                    x: tabBar.bounds.maxX - itemWidth,
                    y: tabBar.bounds.minY,
                    width: itemWidth,
                    height: tabBar.bounds.height
                )
                resolved = tabBar.convert(slice, to: probe)
            }

            guard resolved.isFinite, targetFrame.wrappedValue != resolved else { return }
            targetFrame.wrappedValue = resolved
        }

        func removeOverlay() {
            tabButton?.alpha = 1
            tabButton?.accessibilityElementsHidden = false
            overlay.removeFromSuperview()
        }

        @objc private func pressed() {
            tabButton?.alpha = 0.55
        }

        @objc private func cancelled() {
            tabButton?.alpha = 1
        }

        @objc private func activated() {
            tabButton?.alpha = 1
            onTap()
        }

        private func findTabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for child in view.subviews {
                if let tabBar = findTabBar(in: child) { return tabBar }
            }
            return nil
        }

        // Item controls moved deeper into the hierarchy on newer tab bars, so
        // search recursively (without descending into a matched control) and
        // sort in the bar's coordinate space.
        private func tabButtons(in tabBar: UITabBar) -> [UIView] {
            itemControls(under: tabBar)
                .filter { $0.bounds.width >= 30 && $0.bounds.height >= 30 }
                .sorted {
                    $0.convert($0.bounds, to: tabBar).minX < $1.convert($1.bounds, to: tabBar).minX
                }
        }

        private func itemControls(under view: UIView) -> [UIControl] {
            view.subviews.flatMap { child -> [UIControl] in
                if let control = child as? UIControl, control !== overlay {
                    return [control]
                }
                return itemControls(under: child)
            }
        }
    }

    @MainActor
    final class AgentHitControl: UIControl {
        weak var targetView: UIView?

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            // The target may sit deeper than the bar's direct subviews, so
            // convert into the overlay's space instead of assuming shared coords.
            guard let targetView else { return false }
            return convert(targetView.bounds, from: targetView).contains(point)
        }
    }
}

private extension CGRect {
    var isFinite: Bool {
        [minX, minY, width, height].allSatisfy(\.isFinite)
    }
}
