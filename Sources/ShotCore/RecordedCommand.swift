import Foundation

/// How `shot record --window … -- <command>` ends: with the command's exit code, so `&&` chains still work.
public enum RecordedCommand {
    /// The exit code a shell reports for a child's `waitpid` status: its own code, or 128 plus the signal that ended
    /// it, which is also given.
    public static func exitCode(waitStatus status: Int32) -> (code: Int32, signal: Int32?) {
        let signal = status & 0x7f
        guard signal != 0 else {
            return ((status >> 8) & 0xff, nil)
        }
        return (128 + signal, signal)
    }

    /// Shot's own exit code: the command's when it failed; otherwise the recording's error, if saving it failed, so a
    /// lost recording isn't mistaken for success; otherwise 0.
    public static func exitCode(command: Int32, recording: ShotCommandError?) -> Int32 {
        command != 0 ? command : recording?.exitCode ?? 0
    }
}
