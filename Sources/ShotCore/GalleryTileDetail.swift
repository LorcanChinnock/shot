import Foundation

extension Gallery {
    /// The line under a tile's name: the file's type, then what the sort is by. Date sorts group tiles by day, so they
    /// show the time; Largest first shows the size; Name shows the date.
    public static func tileDetail(for item: GalleryItem, sort: GallerySort, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let type = item.url.pathExtension.uppercased()
        let detail: String
        switch sort {
        case .newest, .oldest:
            var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
            style.timeZone = timeZone
            detail = item.date.formatted(style)
        case .size:
            detail = item.bytes.formatted(.byteCount(style: .file).locale(locale))
        case .name:
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
            style.timeZone = timeZone
            detail = item.date.formatted(style)
        }
        return type.isEmpty ? detail : "\(type) · \(detail)"
    }
}
