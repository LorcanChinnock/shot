import CDBus
import Foundation

/// A private connection to a D-Bus bus through libdbus, without a main loop: a call waits for its reply, and `next`
/// waits for whatever comes after. Use it from one thread at a time.
final class SessionBus: @unchecked Sendable {
    let connection: OpaquePointer
    /// This connection's name on the bus, such as `:1.42`.
    let uniqueName: String

    /// Connects to the bus at `address`, such as `unix:path=/run/user/1000/bus`, and says hello.
    init(address: String) throws(ShotCommandError) {
        var error = DBusError()
        dbus_error_init(&error)
        defer { dbus_error_free(&error) }
        guard let connection = dbus_connection_open_private(address, &error) else {
            throw .unavailable("Shot couldn't connect to the session bus at \(address): \(Self.text(error.message)).")
        }
        guard dbus_bus_register(connection, &error) != 0, let name = dbus_bus_get_unique_name(connection) else {
            dbus_connection_close(connection)
            dbus_connection_unref(connection)
            throw .unavailable("Shot couldn't join the session bus at \(address): \(Self.text(error.message)).")
        }
        // libdbus would end the process when the bus goes away.
        dbus_connection_set_exit_on_disconnect(connection, 0)
        self.connection = connection
        uniqueName = String(cString: name)
    }

    deinit {
        dbus_connection_close(connection)
        dbus_connection_unref(connection)
    }

    /// Calls a method and waits up to `timeout` for its reply.
    func call(_ message: BusMessage, timeout: Duration) throws(BusError) -> BusMessage {
        var error = DBusError()
        dbus_error_init(&error)
        defer { dbus_error_free(&error) }
        guard let reply = dbus_connection_send_with_reply_and_block(connection, message.pointer, Int32(timeout.components.seconds * 1000), &error) else {
            throw BusError(name: Self.text(error.name), message: Self.text(error.message))
        }
        return BusMessage(reply)
    }

    /// Sends a message without waiting for anything back.
    func send(_ message: BusMessage) {
        dbus_connection_send(connection, message.pointer, nil)
        dbus_connection_flush(connection)
    }

    /// Asks the bus for the messages `rule` matches, such as a signal, which it sends only to who asks.
    func addMatch(_ rule: String) throws(BusError) {
        var error = DBusError()
        dbus_error_init(&error)
        defer { dbus_error_free(&error) }
        dbus_bus_add_match(connection, rule, &error)
        if dbus_error_is_set(&error) != 0 {
            throw BusError(name: Self.text(error.name), message: Self.text(error.message))
        }
    }

    func removeMatch(_ rule: String) {
        // Without an error to fill, libdbus doesn't wait for the bus's answer.
        dbus_bus_remove_match(connection, rule, nil)
    }

    /// The next message that comes, or `nil` once `deadline` passes or the bus goes away.
    func next(until deadline: ContinuousClock.Instant) -> BusMessage? {
        while true {
            if let message = dbus_connection_pop_message(connection) {
                return BusMessage(message)
            }
            let left = deadline - .now
            guard left > .zero else {
                return nil
            }
            let milliseconds = left.components.seconds * 1000 + left.components.attoseconds / 1_000_000_000_000_000 + 1
            guard dbus_connection_read_write(connection, Int32(min(milliseconds, 1000))) != 0 else {
                return nil
            }
        }
    }

    static func text(_ string: UnsafePointer<CChar>?) -> String {
        string.map { String(cString: $0) } ?? ""
    }
}

/// A D-Bus error, such as `org.freedesktop.DBus.Error.ServiceUnknown`, with what came with it.
struct BusError: Error, Equatable {
    var name: String
    var message: String
}

/// A D-Bus message, whose arguments go in and come out as `BusValue`s.
final class BusMessage: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Takes over a message libdbus made.
    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        dbus_message_unref(pointer)
    }

    static func call(destination: String, path: String, interface: String, member: String, _ arguments: [BusValue] = []) -> BusMessage {
        let message = BusMessage(dbus_message_new_method_call(destination, path, interface, member))
        message.append(arguments)
        return message
    }

    var type: Int32 { dbus_message_get_type(pointer) }
    var path: String? { dbus_message_get_path(pointer).map { String(cString: $0) } }
    var interface: String? { dbus_message_get_interface(pointer).map { String(cString: $0) } }
    var member: String? { dbus_message_get_member(pointer).map { String(cString: $0) } }

    func isSignal(_ interface: String, _ member: String) -> Bool {
        type == DBUS_MESSAGE_TYPE_SIGNAL && self.interface == interface && self.member == member
    }

    func append(_ arguments: [BusValue]) {
        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(pointer, &iterator)
        for argument in arguments {
            argument.append(to: &iterator)
        }
    }

    /// Its arguments, leaving out those of types `BusValue` doesn't have.
    var arguments: [BusValue] {
        var iterator = DBusMessageIter()
        guard dbus_message_iter_init(pointer, &iterator) != 0 else {
            return []
        }
        return BusValue.read(&iterator)
    }
}

/// How `BusValue`s go into and come out of libdbus's messages.
extension BusValue {
    private static let stringType = Int32(UInt8(ascii: "s")), objectPathType = Int32(UInt8(ascii: "o")), boolType = Int32(UInt8(ascii: "b"))
    private static let uint32Type = Int32(UInt8(ascii: "u")), variantType = Int32(UInt8(ascii: "v")), arrayType = Int32(UInt8(ascii: "a"))
    private static let entryType = Int32(UInt8(ascii: "e")), int32Type = Int32(UInt8(ascii: "i")), unixFDType = Int32(UInt8(ascii: "h"))
    private static let structureType = Int32(UInt8(ascii: "r"))

    func append(to iterator: inout DBusMessageIter) {
        switch self {
        case let .string(text):
            Self.append(text, as: Self.stringType, to: &iterator)
        case let .objectPath(text):
            Self.append(text, as: Self.objectPathType, to: &iterator)
        case let .bool(value):
            var bool: dbus_bool_t = value ? 1 : 0
            dbus_message_iter_append_basic(&iterator, Self.boolType, &bool)
        case let .uint32(value):
            var number = value
            dbus_message_iter_append_basic(&iterator, Self.uint32Type, &number)
        case let .int32(value):
            var number = value
            dbus_message_iter_append_basic(&iterator, Self.int32Type, &number)
        case let .unixFD(fd):
            // libdbus sends a duplicate of it.
            var descriptor = fd
            dbus_message_iter_append_basic(&iterator, Self.unixFDType, &descriptor)
        case let .variant(value):
            Self.open(&iterator, Self.variantType, value.signature) { value.append(to: &$0) }
        case let .dictionary(entries):
            Self.open(&iterator, Self.arrayType, "{sv}") { array in
                for key in entries.keys.sorted() {
                    Self.open(&array, Self.entryType, nil) { entry in
                        BusValue.string(key).append(to: &entry)
                        BusValue.variant(entries[key]!).append(to: &entry)
                    }
                }
            }
        case let .array(values):
            Self.open(&iterator, Self.arrayType, String(signature.dropFirst())) { array in
                for value in values {
                    value.append(to: &array)
                }
            }
        case let .structure(values):
            Self.open(&iterator, Self.structureType, nil) { structure in
                for value in values {
                    value.append(to: &structure)
                }
            }
        }
    }

    private static func append(_ text: String, as type: Int32, to iterator: inout DBusMessageIter) {
        text.withCString { characters in
            var pointer: UnsafePointer<CChar>? = characters
            _ = dbus_message_iter_append_basic(&iterator, type, &pointer)
        }
    }

    private static func open(_ iterator: inout DBusMessageIter, _ type: Int32, _ signature: String?, _ fill: (inout DBusMessageIter) -> Void) {
        var inner = DBusMessageIter()
        if let signature {
            dbus_message_iter_open_container(&iterator, type, signature, &inner)
        } else {
            dbus_message_iter_open_container(&iterator, type, nil, &inner)
        }
        fill(&inner)
        dbus_message_iter_close_container(&iterator, &inner)
    }

    /// The values from `iterator` on.
    static func read(_ iterator: inout DBusMessageIter) -> [BusValue] {
        var values: [BusValue] = []
        repeat {
            if let value = readOne(&iterator) {
                values.append(value)
            }
        } while dbus_message_iter_next(&iterator) != 0
        return values
    }

    private static func readOne(_ iterator: inout DBusMessageIter) -> BusValue? {
        switch dbus_message_iter_get_arg_type(&iterator) {
        case stringType, objectPathType:
            var pointer: UnsafePointer<CChar>?
            dbus_message_iter_get_basic(&iterator, &pointer)
            let text = SessionBus.text(pointer)
            return dbus_message_iter_get_arg_type(&iterator) == stringType ? .string(text) : .objectPath(text)
        case boolType:
            var bool: dbus_bool_t = 0
            dbus_message_iter_get_basic(&iterator, &bool)
            return .bool(bool != 0)
        case uint32Type:
            var number: UInt32 = 0
            dbus_message_iter_get_basic(&iterator, &number)
            return .uint32(number)
        case int32Type:
            var number: Int32 = 0
            dbus_message_iter_get_basic(&iterator, &number)
            return .int32(number)
        case unixFDType:
            // A duplicate, which the reader owns.
            var fd: Int32 = -1
            dbus_message_iter_get_basic(&iterator, &fd)
            return .unixFD(fd)
        case structureType:
            var inner = DBusMessageIter()
            dbus_message_iter_recurse(&iterator, &inner)
            return .structure(dbus_message_iter_get_arg_type(&inner) == 0 ? [] : read(&inner))
        case variantType:
            var inner = DBusMessageIter()
            dbus_message_iter_recurse(&iterator, &inner)
            return readOne(&inner).map(BusValue.variant)
        case arrayType:
            var inner = DBusMessageIter()
            dbus_message_iter_recurse(&iterator, &inner)
            guard dbus_message_iter_get_arg_type(&inner) != 0 else {
                return .array([])
            }
            guard dbus_message_iter_get_arg_type(&inner) == entryType else {
                return .array(read(&inner))
            }
            var entries: [String: BusValue] = [:]
            repeat {
                var entry = DBusMessageIter()
                dbus_message_iter_recurse(&inner, &entry)
                guard case let .string(key)? = readOne(&entry), dbus_message_iter_next(&entry) != 0, let value = readOne(&entry) else {
                    continue
                }
                if case let .variant(inside) = value {
                    entries[key] = inside
                } else {
                    entries[key] = value
                }
            } while dbus_message_iter_next(&inner) != 0
            return .dictionary(entries)
        default:
            return nil
        }
    }
}
