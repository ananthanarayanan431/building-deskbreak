import Foundation

/// Reads and writes the reminder log as one JSON file in the app's own Application Support folder.
///
/// Safety rule: this is the only code in the app that writes files. Every write goes through
/// `write(_:to:)`, which accepts only the two fixed file names below inside `directory`.
/// There is no user-supplied path and no delete operation.
public struct LogFileStore: Sendable {
    public static let folderName = "DeskBreak"
    static let logFileName = "reminder-log.json"
    static let quarantineFileName = "reminder-log.unreadable.json"
    static let schemaVersion = 1

    public enum StoreError: Error, LocalizedError {
        case unsupportedSchema(Int)
        case pathOutsideStore(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                "The reminder log was written by a newer version (schema \(version))."
            case .pathOutsideStore(let path):
                "Refusing to write outside the app's data folder: \(path)"
            }
        }
    }

    /// The app's private data folder.
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent(Self.logFileName, isDirectory: false) }
    var quarantineURL: URL { directory.appendingPathComponent(Self.quarantineFileName, isDirectory: false) }

    /// - Parameter applicationSupportDirectory: the parent folder. Production code uses `standard()`;
    ///   tests pass a temporary directory.
    public init(applicationSupportDirectory: URL) {
        directory = applicationSupportDirectory
            .appendingPathComponent(Self.folderName, isDirectory: true)
            .standardizedFileURL
    }

    /// The store at `~/Library/Application Support/DeskBreak/`.
    public static func standard() throws -> LogFileStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return LogFileStore(applicationSupportDirectory: base)
    }

    // MARK: Reading

    /// Loads the log. A missing file yields an empty log. An unreadable file is copied aside
    /// (so nothing is silently lost) and an empty log is returned.
    public func load() throws -> ReminderLog {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return ReminderLog()
        }

        do {
            let file = try Self.decoder.decode(LogFile.self, from: data)
            guard file.schemaVersion <= Self.schemaVersion else {
                throw StoreError.unsupportedSchema(file.schemaVersion)
            }
            return ReminderLog(records: file.records)
        } catch let error as StoreError {
            // Never overwrite a log written by a newer version.
            throw error
        } catch {
            try write(data, to: quarantineURL)
            return ReminderLog()
        }
    }

    // MARK: Writing

    public func save(_ log: ReminderLog) throws {
        let file = LogFile(schemaVersion: Self.schemaVersion, records: log.records)
        let data = try Self.encoder.encode(file)
        try write(data, to: fileURL)
    }

    /// The single write path. Writes atomically (temporary file, then rename) so a crash or power
    /// loss cannot leave a half-written file.
    private func write(_ data: Data, to url: URL) throws {
        let target = url.standardizedFileURL
        guard target == fileURL.standardizedFileURL || target == quarantineURL.standardizedFileURL else {
            throw StoreError.pathOutsideStore(target.path)
        }
        try ensureDirectory()
        try data.write(to: target, options: [.atomic])
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    // MARK: Format

    private struct LogFile: Codable {
        var schemaVersion: Int
        var records: [ReminderRecord]
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
