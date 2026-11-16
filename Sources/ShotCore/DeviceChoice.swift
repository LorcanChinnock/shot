/// What a microphone or camera picker in Settings shows as chosen, given the saved device and the ones connected now.
///
/// A saved device that isn't connected stays saved, and macOS hands it back to Shot the moment it's plugged in again, so
/// the picker names it as not connected rather than ticking System default, which would hide that it can come back.
public enum DeviceChoice: Equatable, Sendable {
    /// Nothing saved: Shot uses the device macOS uses.
    case systemDefault
    /// The saved device, connected now.
    case connected(id: String)
    /// A saved device that isn't connected, with the name it had when it was picked (empty when it was picked before
    /// Shot saved names). Recording falls back to the system default until it's connected again.
    case missing(name: String)

    public init(savedID: String, savedName: String, connectedIDs: [String]) {
        if savedID.isEmpty {
            self = .systemDefault
        } else if connectedIDs.contains(savedID) {
            self = .connected(id: savedID)
        } else {
            self = .missing(name: savedName)
        }
    }
}
