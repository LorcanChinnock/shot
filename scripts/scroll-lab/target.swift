import AppKit
// A scroll target for live scroll-lab runs: shows a tall truth image in a real NSScrollView with overlay scrollers.
// usage: ScrollTarget <truth.png> <viewWidthPt> <viewHeightPt> <screenX> <screenYTop>
let a = CommandLine.arguments
let image = NSImage(contentsOfFile: a[1])!
let rep = image.representations[0]
let w = CGFloat(Double(a[2])!), h = CGFloat(Double(a[3])!)
let docH = CGFloat(rep.pixelsHigh) / 2
image.size = NSSize(width: w, height: docH)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: h))
scroll.scrollerStyle = .overlay
scroll.hasVerticalScroller = true
scroll.autohidesScrollers = true
let view = NSImageView(frame: NSRect(x: 0, y: 0, width: w, height: docH))
view.image = image
view.imageScaling = .scaleNone
scroll.documentView = view
let screenH = NSScreen.main!.frame.height
let window = NSWindow(contentRect: NSRect(x: CGFloat(Double(a[4])!), y: screenH - CGFloat(Double(a[5])!) - h, width: w, height: h), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "ScrollTarget"
window.contentView = scroll
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
// Start at the top.
scroll.contentView.scroll(to: NSPoint(x: 0, y: docH - h))
scroll.reflectScrolledClipView(scroll.contentView)
app.run()
