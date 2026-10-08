/// Keys in order of last use, each with a cost, keeping the total within `limit` by dropping the least recently used.
public struct RecentlyUsed<Key: Hashable> {
    public let limit: Int
    public private(set) var total = 0
    private var order: [Key] = []
    private var costs: [Key: Int] = [:]

    public init(limit: Int) {
        self.limit = limit
    }

    public var isEmpty: Bool { order.isEmpty }

    /// Marks `key` as just used, adding it at `cost` if it's new, and returns the keys dropped to stay within the limit.
    /// `key` itself is never dropped, even when it costs more than the limit alone.
    public mutating func use(_ key: Key, cost: Int) -> [Key] {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        } else {
            costs[key] = cost
            total += cost
        }
        order.append(key)
        var dropped: [Key] = []
        while total > limit, order.count > 1 {
            let oldest = order.removeFirst()
            total -= costs.removeValue(forKey: oldest) ?? 0
            dropped.append(oldest)
        }
        return dropped
    }

    public mutating func removeAll() {
        order.removeAll()
        costs.removeAll()
        total = 0
    }
}
