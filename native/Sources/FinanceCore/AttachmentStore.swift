import Foundation
import CryptoKit

public enum AttachmentError: Error, LocalizedError {
    case unsupportedType
    case tooLarge
    case unreadable(String)
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "Als Beleg sind nur PDF, JPEG, PNG, HEIC und TIFF möglich."
        case .tooLarge: "Der Beleg ist größer als 25 MB."
        case .unreadable(let name): "Der Beleg „\(name)“ konnte nicht gelesen werden."
        case .invalidName: "Der Dateiname des Belegs ist ungültig."
        }
    }
}

/// Content-addressed storage for receipt files. Files are copied next to the
/// database and named `<sha256>.<ext>`, so identical receipts share one file and
/// no user-controlled name ever becomes a path.
public struct AttachmentStore: Sendable {
    public static let maximumFileSize = 25 * 1_048_576
    private static let canonicalExtensions = ["pdf": "pdf", "jpg": "jpg", "jpeg": "jpg", "png": "png", "heic": "heic", "tif": "tif", "tiff": "tif"]
    private static let storedExtensions: Set<String> = ["pdf", "jpg", "png", "heic", "tif"]

    public struct StoredFile: Sendable {
        public let fileName: String
        public let storedName: String
        public let sha256: String
        public let sizeBytes: Int
        /// False when an identical file was already in the store.
        public let wasCreated: Bool
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func isValidStoredName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 64, storedExtensions.contains(String(parts[1])) else { return false }
        return parts[0].allSatisfy { $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }
    }

    /// Checks type, size and file signature before anything is copied.
    @discardableResult
    public static func validate(_ url: URL) throws -> (size: Int, fileExtension: String) {
        let name = url.lastPathComponent
        guard let fileExtension = canonicalExtensions[url.pathExtension.lowercased()] else { throw AttachmentError.unsupportedType }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw AttachmentError.unreadable(name) }
        guard size <= maximumFileSize else { throw AttachmentError.tooLarge }
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw AttachmentError.unreadable(name) }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 1_024), matchesSignature(header, fileExtension: fileExtension) else {
            throw AttachmentError.unsupportedType
        }
        return (size, fileExtension)
    }

    private static func matchesSignature(_ header: Data, fileExtension: String) -> Bool {
        let bytes = [UInt8](header)
        switch fileExtension {
        case "pdf": return header.range(of: Data("%PDF".utf8)) != nil
        case "jpg": return bytes.starts(with: [0xFF, 0xD8, 0xFF])
        case "png": return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47])
        case "heic": return bytes.count >= 12 && Array(bytes[4..<8]) == Array("ftyp".utf8)
        case "tif": return bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
        default: return false
        }
    }

    public func importFile(at source: URL) throws -> StoredFile {
        let (_, fileExtension) = try Self.validate(source)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appending(path: ".tmp-\(UUID().uuidString)")
        do {
            try fileManager.copyItem(at: source, to: temporary)
        } catch {
            throw AttachmentError.unreadable(source.lastPathComponent)
        }
        defer { try? fileManager.removeItem(at: temporary) }

        let (digest, size) = try Self.hash(of: temporary, name: source.lastPathComponent)
        guard size <= Self.maximumFileSize else { throw AttachmentError.tooLarge }
        let storedName = "\(digest).\(fileExtension)"
        let target = directory.appending(path: storedName)
        var created = false
        if !fileManager.fileExists(atPath: target.path) {
            try fileManager.moveItem(at: temporary, to: target)
            created = true
        }
        return StoredFile(fileName: source.lastPathComponent, storedName: storedName, sha256: digest, sizeBytes: size, wasCreated: created)
    }

    public func fileURL(storedName: String) -> URL? {
        Self.isValidStoredName(storedName) ? directory.appending(path: storedName) : nil
    }

    public func fileExists(storedName: String) -> Bool {
        fileURL(storedName: storedName).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    public func remove(storedName: String) {
        guard let url = fileURL(storedName: storedName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func totalSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        return enumerator.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
    }

    private static func hash(of url: URL, name: String) throws -> (String, Int) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw AttachmentError.unreadable(name) }
        defer { try? handle.close() }
        var hasher = SHA256()
        var size = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += chunk.count
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}
