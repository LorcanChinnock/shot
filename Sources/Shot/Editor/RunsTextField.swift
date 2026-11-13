import AppKit
import Carbon.HIToolbox
import ShotCore

/// The field the image and video editors type a text or a note into. It shows each part of the text in its own size, and
/// keeps those sizes, in image pixels, in an attribute of its own, so they last through typing, pasting, undo and any
/// zoom. Typing takes the size of the text before the caret, as any Mac text field does. While it's open, the text and
/// sizes it holds are the ones being typed; `text` and `sizes` read them.
///
/// Return and Shift-Return start a new line; Esc and ⌘Return call `onFinish`. Clicking another field, such as the style
/// bar's size box, leaves it open with what was selected, rather than ending the edit, so the size box can size the
/// selection.
final class RunsTextField: NSTextField {
    private static let sizeKey = NSAttributedString.Key("dev.lorcan.Shot.textSize")

    /// Bold for text, regular for a note.
    private var bold = true
    /// View points per image pixel.
    private var viewScale: CGFloat = 1
    private var ink = NSColor.black
    private var textAlignment = NSTextAlignment.left
    /// The size, in pixels, that text typed into the empty field takes.
    private var emptySize: CGFloat = 12
    /// What was selected when the keyboard last went elsewhere, put back when it comes back.
    private var savedSelection: NSRange?
    /// Called as the selection changes while typing.
    var onSelectionChange: (() -> Void)?
    /// Called when undo or redo puts back sizes, once the field shows them.
    var onSizesChange: (() -> Void)?
    /// Called when Esc or ⌘Return finishes typing.
    var onFinish: (() -> Void)?

    /// A field holding `annotation`'s text in its sizes, for a text in bold or a note in regular.
    init(annotation: Annotation) {
        super.init(frame: .zero)
        bold = if case .note = annotation.kind { false } else { true }
        emptySize = annotation.textSize ?? emptySize
        allowsEditingTextAttributes = true
        importsGraphics = false
        let text = annotation.text ?? ""
        attributedStringValue = attributed(text, sizes: annotation.textRuns ?? TextRuns(length: text.utf16.count, size: emptySize))
        NotificationCenter.default.addObserver(self, selector: #selector(selectionDidChange), name: NSTextView.didChangeSelectionNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var editor: NSTextView? { currentEditor() as? NSTextView }

    /// What's typed so far, with its attributes.
    private var content: NSAttributedString { editor?.textStorage ?? attributedStringValue }

    var text: String { content.string }

    /// The size of each part of what's typed, in pixels. Text pasted in without one takes the size before it.
    var sizes: TextRuns {
        Self.sizes(of: content, fallback: emptySize)
    }

    /// What's selected while typing, or was when the keyboard went elsewhere, in UTF-16 code units.
    var selection: Range<Int>? {
        let range = editor?.selectedRange() ?? savedSelection
        return range.flatMap { Range($0) }
    }

    /// Shows the text at `viewScale`, in `color` and lined up by `alignment`; text typed into the empty field takes
    /// `emptySize`. Nothing changes while an input method is composing.
    func restyle(emptySize: CGFloat, color: NSColor, alignment: NSTextAlignment, viewScale: CGFloat) {
        self.emptySize = emptySize
        ink = color
        textAlignment = alignment
        self.viewScale = viewScale
        // The field's own font and alignment would replace the text's, so they're set only for the placeholder.
        if text.isEmpty {
            font = font(size: emptySize)
            self.alignment = alignment
        }
        // A note's placeholder is in the note's text colour, as what's typed will be.
        if let placeholder = placeholderAttributedString?.string ?? placeholderString, !placeholder.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .font: font(size: emptySize), .foregroundColor: color, .paragraphStyle: paragraph,
            ])
        }
        if editor?.hasMarkedText() == true {
            return
        }
        apply(sizes)
    }

    /// Gives the text these sizes as one undo step of the field's typing. If the keyboard went to another field, such as
    /// the size box, the field takes it back afterwards, with the selection it had, once that field has let it go.
    func setSizes(_ newSizes: TextRuns) {
        let old = sizes
        guard newSizes.length == old.length, !newSizes.isClose(to: old) else {
            return
        }
        apply(newSizes)
        editor?.breakUndoCoalescing()
        (editor?.undoManager ?? window?.undoManager)?.registerUndo(withTarget: self) { field in
            field.setSizes(old)
            field.onSizesChange?()
        }
        if editor == nil {
            Task { @MainActor [weak self] in
                guard let self, superview != nil, editor == nil else {
                    return
                }
                takeKeyboard()
            }
        }
    }

    /// Makes this the field typed in, with what was selected before the keyboard went elsewhere.
    func takeKeyboard() {
        let selected = savedSelection
        window?.makeFirstResponder(self)
        if let editor, let selected, NSMaxRange(selected) <= (editor.string as NSString).length {
            editor.setSelectedRange(selected)
        }
    }

    /// Handles a command the field editor is about to perform, from the delegate's `control(_:textView:doCommandBy:)`:
    /// Esc and ⌘Return finish, and Return starts a new line rather than ending the edit. An input method takes the Return
    /// that confirms its text, but if one reaches here mid-composition it confirms the text rather than adding a line.
    func perform(_ command: Selector, in textView: NSTextView) -> Bool {
        switch command {
        case #selector(NSResponder.cancelOperation(_:)):
            onFinish?()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                onFinish?()
            } else if textView.hasMarkedText() {
                Self.confirmComposition(in: textView)
            } else {
                textView.insertNewlineIgnoringFieldEditor(nil)
            }
            return true
        default:
            return false
        }
    }


    /// Finishes the typing in `window` on ⌘Return. It's a key equivalent, which the window takes before the field editor
    /// sees the key, so the editors' windows offer it here first.
    static func finishTyping(on event: NSEvent, in window: NSWindow) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command, [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)),
              let editor = window.firstResponder as? NSTextView, let field = editor.delegate as AnyObject? as? RunsTextField, let onFinish = field.onFinish
        else {
            return false
        }
        if editor.hasMarkedText() {
            confirmComposition(in: editor)
        }
        onFinish()
        return true
    }

    /// Keeps the text an input method is composing as typed and ends its session.
    private static func confirmComposition(in editor: NSTextView) {
        editor.unmarkText()
        editor.inputContext?.discardMarkedText()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            window?.undoManager?.removeAllActions(withTarget: self)
        }
    }

    override func textDidChange(_ notification: Notification) {
        if editor?.hasMarkedText() != true {
            apply(sizes)
        }
        super.textDidChange(notification)
    }

    override func textDidEndEditing(_ notification: Notification) {
        savedSelection = (notification.object as? NSTextView)?.selectedRange()
        // A click in another field moves the keyboard without ending the edit.
        guard notification.userInfo?["NSTextMovement"] as? Int == NSTextMovement.other.rawValue, let cell else {
            super.textDidEndEditing(notification)
            return
        }
        let sends = cell.sendsActionOnEndEditing
        cell.sendsActionOnEndEditing = false
        super.textDidEndEditing(notification)
        cell.sendsActionOnEndEditing = sends
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        guard let editor, notification.object as AnyObject? === editor else {
            return
        }
        savedSelection = editor.selectedRange()
        onSelectionChange?()
    }

    // MARK: Attributes

    private func font(size: CGFloat) -> NSFont {
        let points = max(1, size * viewScale)
        return bold ? .boldSystemFont(ofSize: points) : .systemFont(ofSize: points)
    }

    private func attributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        return [.font: font(size: size), .foregroundColor: ink, .paragraphStyle: paragraph, Self.sizeKey: size]
    }

    private func attributed(_ text: String, sizes: TextRuns) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text)
        set(sizes, on: string)
        return string
    }

    /// Puts `sizes` on `string`, with nothing else but the font, colour and alignment they're shown in.
    private func set(_ sizes: TextRuns, on string: NSMutableAttributedString) {
        var start = 0
        for run in sizes.runs where start + run.length <= string.length {
            string.setAttributes(attributes(size: run.size), range: NSRange(location: start, length: run.length))
            start += run.length
        }
    }

    /// Shows `sizes`, in the field editor while typing, else in the field.
    private func apply(_ sizes: TextRuns) {
        if let editor, let storage = editor.textStorage {
            guard sizes.length == storage.length else {
                return
            }
            storage.beginEditing()
            set(sizes, on: storage)
            storage.endEditing()
            let caret = editor.selectedRange()
            let typing = (caret.length > 0 ? sizes.size(at: caret.location) : sizes.caretSize(at: caret.location)) ?? emptySize
            editor.typingAttributes = attributes(size: typing)
        } else {
            let string = NSMutableAttributedString(attributedString: attributedStringValue)
            guard sizes.length == string.length else {
                return
            }
            set(sizes, on: string)
            attributedStringValue = string
        }
    }

    /// The sizes in `content`'s attribute; a part without one takes the size before it, or after it at the start.
    private static func sizes(of content: NSAttributedString, fallback: CGFloat) -> TextRuns {
        var runs: [(length: Int, size: CGFloat?)] = []
        content.enumerateAttribute(sizeKey, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            runs.append((range.length, (value as? NSNumber).map { CGFloat($0.doubleValue) }))
        }
        let first = runs.lazy.compactMap(\.size).first ?? fallback
        var previous = first
        return TextRuns(runs.map { run in
            let size = run.size ?? previous
            previous = size
            return TextRun(length: run.length, size: size)
        })
    }
}
