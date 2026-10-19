import Foundation

/// Writes Shot's XMP properties and reads simple ones back, as attributes or elements of a description, which is how
/// ImageIO writes them: elements in a PNG, attributes in a JPEG. It reads only what Shot needs, not all of RDF.
enum XMP {
    static let noteNamespace = "http://ns.adobe.com/xmp/note/"

    /// A packet with `properties` in Shot's namespace. `extendedGUID` says the rest is in extended XMP segments, and an
    /// extended part itself isn't `wrapped` in an `xpacket`.
    static func packet(_ properties: [(name: String, value: String)], extendedGUID: String? = nil, wrapped: Bool = true) -> String {
        var description = "<rdf:Description rdf:about=\"\" xmlns:shot=\"\(ImageMetadata.xmpNamespace)\""
        if let extendedGUID {
            description += " xmlns:xmpNote=\"\(noteNamespace)\" xmpNote:HasExtendedXMP=\"\(extendedGUID)\""
        }
        description += ">" + properties.map { "<shot:\($0.name)>\(escaped($0.value))</shot:\($0.name)>" }.joined() + "</rdf:Description>"
        let meta = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\(description)</rdf:RDF></x:xmpmeta>"
        return wrapped ? "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\(meta)<?xpacket end=\"w\"?>" : meta
    }

    /// The text of the property `name` in `namespace`, whatever prefix `xml` binds it to, or `nil` when it has none.
    static func property(_ name: String, namespace: String, in xml: String) -> String? {
        guard let prefix = prefix(of: namespace, in: xml) else {
            return nil
        }
        let qualified = "\(prefix):\(name)"
        var searchStart = xml.startIndex
        while let found = xml.range(of: qualified, range: searchStart ..< xml.endIndex) {
            searchStart = found.upperBound
            guard found.lowerBound > xml.startIndex else {
                continue
            }
            let before = xml[xml.index(before: found.lowerBound)]
            let after = xml[found.upperBound...]
            if before.isWhitespace, after.hasPrefix("=\"") || after.hasPrefix("='") {
                let quote = after.dropFirst().first!
                let value = after.dropFirst(2)
                if let end = value.firstIndex(of: quote) {
                    return unescaped(value[..<end])
                }
            } else if before == "<", let open = after.firstIndex(of: ">"), let next = after.first, next == ">" || next == "/" || next.isWhitespace {
                guard xml[xml.index(before: open)] != "/" else {
                    return ""
                }
                let value = xml[xml.index(after: open)...]
                if let close = value.range(of: "</\(qualified)>") {
                    return unescaped(value[..<close.lowerBound])
                }
            }
        }
        return nil
    }

    /// The prefix an `xmlns:` attribute binds to `namespace`.
    private static func prefix(of namespace: String, in xml: String) -> String? {
        for quote in ["\"", "'"] {
            guard let binding = xml.range(of: "=\(quote)\(namespace)\(quote)"), let xmlns = xml.range(of: "xmlns:", options: .backwards, range: xml.startIndex ..< binding.lowerBound) else {
                continue
            }
            let prefix = xml[xmlns.upperBound ..< binding.lowerBound]
            if !prefix.isEmpty, !prefix.contains(where: \.isWhitespace) {
                return String(prefix)
            }
        }
        return nil
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func unescaped(_ text: Substring) -> String {
        guard text.contains("&") else {
            return String(text)
        }
        let named: [Substring: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        var result = "", rest = text
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let entity = rest[rest.index(after: amp)...]
            guard let semicolon = entity.prefix(10).firstIndex(of: ";") else {
                result += "&"
                rest = entity
                continue
            }
            let name = entity[..<semicolon]
            let number = name.hasPrefix("#x") ? UInt32(name.dropFirst(2), radix: 16) : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            if let character = named[name] ?? number.flatMap(Unicode.Scalar.init).map(String.init) {
                result += character
                rest = entity[entity.index(after: semicolon)...]
            } else {
                result += "&"
                rest = entity
            }
        }
        return result + rest
    }
}
