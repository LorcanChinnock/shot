import CoreGraphics

/// Whether a Settings row keeps its control beside its name or moves it underneath. A long translation or a larger text
/// size can leave a control that can't shrink, such as a segmented control or a button, wider than the row allows; side
/// by side, the name would then break a letter or a word to a line.
public enum SettingRowFit {
    /// The room a name with a description needs beside its control: the description wraps, so it only needs to be
    /// readable, not to fit on one line.
    public static let minimumTitleWidth: CGFloat = 120

    /// True when the control goes under the name. `controlWidth` is the narrowest the control can be, and `titleWidth`
    /// the name's width on one line (with its description, if any).
    public static func stacks(width: CGFloat, controlWidth: CGFloat, titleWidth: CGFloat, spacing: CGFloat) -> Bool {
        width - controlWidth - spacing < min(titleWidth, minimumTitleWidth)
    }
}
