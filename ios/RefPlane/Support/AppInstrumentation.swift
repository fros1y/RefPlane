import os
import os.signpost

enum AppInstrumentation {

    static let subsystem = "com.refplane.app"

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static func signpostLog(category: String) -> OSLog {
        OSLog(subsystem: subsystem, category: category)
    }

    @discardableResult
    static func measure<T>(
        _ name: StaticString,
        log: OSLog,
        _ operation: () throws -> T
    ) rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
        return try operation()
    }

    @discardableResult
    static func measure<T>(
        _ name: StaticString,
        log: OSLog,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
        return try await operation()
    }
}