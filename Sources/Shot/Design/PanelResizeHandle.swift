import AppKit
import SwiftUI

/// A strip on the edge of a side panel that resizes it when dragged. Double-click puts it back to its usual width.
/// Dragging well past the narrowest width collapses the panel, when `onCollapse` is given. It sits in the gap beside the
/// panel, for a panel on the left; the caller places it.
struct PanelResizeHandle: View {
    @Binding var width: Double
    /// The narrowest and widest the panel can be dragged to.
    let range: ClosedRange<Double>
    let defaultWidth: Double
    var onCollapse: (() -> Void)?
    @State private var startWidth: Double?
    @State private var hovering = false

    /// How far past the narrowest width a drag has to go to collapse the panel.
    private static let collapseDistance: Double = 50

    var body: some View {
        Color.clear
            .frame(width: 14)
            .overlay {
                Capsule()
                    .fill(Brutal.ink.opacity(hovering || startWidth != nil ? 0.4 : 0))
                    .frame(width: 4, height: 40)
            }
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(max(start + drag.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { drag in
                        let proposed = (startWidth ?? width) + drag.translation.width
                        startWidth = nil
                        if proposed < range.lowerBound - Self.collapseDistance {
                            onCollapse?()
                            width = defaultWidth
                        }
                    }
            )
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2 {
                    width = defaultWidth
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Resize panel"))
            .accessibilityValue(Text("\(Int(width)) points wide"))
            .accessibilityAdjustableAction { direction in
                let step = 20.0
                switch direction {
                case .increment: width = min(width + step, range.upperBound)
                case .decrement: width = max(width - step, range.lowerBound)
                @unknown default: break
                }
            }
            .help(Text("Drag to resize. Double-click to reset."))
    }
}
