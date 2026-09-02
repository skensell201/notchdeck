import OSLog

public enum Log {
    public static let subsystem = "com.skensell.notchdeck"

    public static func make(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
