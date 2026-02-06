import Foundation
import CryptoKit
import AppKit

enum GenericHelper {

    static func getAppSupportDirectory() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.whisperclip"
        let dir = appSupport.appendingPathComponent(bundleID)
        return dir
    }

    static func folderCreate(folder: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
    }

    static func fileExists(file: URL) -> Bool {
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: file.path)
        return exists
    }

    static func deleteFile(file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
            if GenericHelper.logSensitiveData() {
                Logger.log("Deleted file at \(file.path)", log: Logger.audio)
            }
        } catch {
            if GenericHelper.logSensitiveData() {
                Logger.log("Failed to delete file: \(error)", log: Logger.audio, type: .error)
            }
        }
    }

    static func folderExists(folder: URL) -> Bool {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        let exists = fileManager.fileExists(atPath: folder.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    static func folderCleanOldFiles(folder: URL, days: Int) {
        // 1. Validate days
        guard days > 0 else {
            Logger.log("Invalid days parameter (\(days)); must be ≥ 1",
                    log: Logger.general,
                    type: .debug)
            return
        }

        // 2. Ensure folder exists and is a directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            Logger.log("Folder \(folder.path) does not exist or is not a directory",
                    log: Logger.general,
                    type: .debug)
            return
        }

        // 3. Compute cutoff date
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            Logger.log("Failed to compute cutoff date", log: Logger.general, type: .error)
            return
        }

        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for fileURL in contents {
                do {
                    let values = try fileURL.resourceValues(forKeys: resourceKeys)
                    // Only delete regular files older than cutoffDate
                    if values.isDirectory == false,
                    let modDate = values.contentModificationDate,
                    modDate < cutoffDate
                    {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            if logSensitiveData() {
                                Logger.log("Deleted old file: \(fileURL.lastPathComponent)",
                                        log: Logger.general)
                            }
                        } catch {
                            Logger.log("Failed to delete \(fileURL.lastPathComponent): \(error)",
                                    log: Logger.general,
                                    type: .error)
                        }
                    }
                } catch {
                    Logger.log("Error reading attributes of \(fileURL.lastPathComponent): \(error)",
                            log: Logger.general,
                            type: .error)
                }
            }
        } catch {
            Logger.log("Error listing contents of \(folder.path): \(error)",
                    log: Logger.general,
                    type: .error)
        }
    }

    static func folderSize(folder: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    static func formatSize(size: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func getBytesHash(bytes: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: bytes)
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func getFileHash(file: URL) throws -> String {
        var hasher = SHA256()
        let chunkSize = 1 * 1024 * 1024  // 1 MB

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            Logger.log("Cannot open \(file.path)", log: Logger.general)
            throw NSError(domain: "sha256Dir", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot open \(file.path)"])
        }
        defer { try? handle.close() }

        while true {
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute the SHA-256 digest of the *entire* directory at `directory`,
    /// by streaming each file (in lex order) into one hasher,
    /// skipping only a top-level file named `skipFilename` (if non‐nil).
    static func getDirectoryHash(ofDirectory directory: URL, skipping skipFilename: String?) throws -> String {
        let fm = FileManager.default

        if !folderExists(folder: directory) {
            Logger.log("Directory \(directory.path) does not exist", log: Logger.general)
            throw NSError(domain: "sha256Dir", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Directory \(directory.path) does not exist"])
        }

        // 1. Enumerate recursively, skipping hidden
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { (url, err) -> Bool in
                Logger.log("Warning: cannot access \(url.path): \(err)", log: Logger.general)
                return true
            })
        else {
            Logger.log("Failed to enumerate \(directory.path)", log: Logger.general)
            throw NSError(domain: "sha256Dir", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to enumerate \(directory.path)"])
        }

        // 2. Collect & sort
        var fileURLs: [URL] = []
        for case let url as URL in enumerator {
            let props = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard props.isRegularFile == true else { continue }

            // if skipFilename is set, only skip if:
            //   • its lastPathComponent matches, AND
            //   • its parent directory is exactly the root
            if let skip = skipFilename,
            url.lastPathComponent == skip,
            url.deletingLastPathComponent() == directory {
                continue
            }

            fileURLs.append(url)
        }
        fileURLs.sort { $0.path < $1.path }

        // 3. Single hasher
        var hasher = SHA256()
        let chunkSize = 1 * 1024 * 1024  // 1 MB

        // 4. Stream each file's bytes
        for fileURL in fileURLs {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                Logger.log("Cannot open \(fileURL.path)", log: Logger.general)
                throw NSError(domain: "sha256Dir", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Cannot open \(fileURL.path)"])
            }
            defer { try? handle.close() }

            while true {
                let data = handle.readData(ofLength: chunkSize)
                if data.isEmpty { break }
                hasher.update(data: data)
            }
        }

        // 5. Finalize and hex
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func getUnixTimestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970)
    }

    static func unixTimestampToString(timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func xorEncoder(data: Data, key: Data) -> Data {
        var encoded = data
        for i in 0..<encoded.count {
            encoded[i] ^= key[i % key.count]
        }
        return encoded
    }

    enum AESGCMError: Error {
        case invalidKeySize
        case sealingFailed
    }

    /// Encrypts `plaintext` with AES-GCM using the given raw key.
    /// - Parameters:
    ///   - plaintext: the data you want to encrypt
    ///   - keyData: raw key bytes (16/24/32 bytes for AES-128/192/256)
    /// - Returns: combined nonce + ciphertext + tag
    static func aesEncrypt(plaintext: Data, keyData: Data) throws -> Data {
        guard [16, 24, 32].contains(keyData.count) else {
            throw AESGCMError.invalidKeySize
        }
        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw AESGCMError.sealingFailed
        }
        return combined
    }

    /// Decrypts data produced by `aesEncrypt`.
    /// - Parameters:
    ///   - sealedData: the nonce+ciphertext+tag blob from `aesEncrypt`
    ///   - keyData: the same raw key bytes used to encrypt
    /// - Returns: the original plaintext
    static func aesDecrypt(sealedData: Data, keyData: Data) throws -> Data {
        guard [16, 24, 32].contains(keyData.count) else {
            throw AESGCMError.invalidKeySize
        }
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: sealedData)
        let decrypted = try AES.GCM.open(box, using: key)
        return decrypted
    }

    static func logToConsole() -> Bool {
        return ProcessInfo.processInfo.environment["LOG_TO_CONSOLE"] == "1"
    }

    static func logSensitiveData() -> Bool {
        return ProcessInfo.processInfo.environment["LOG_SENSITIVE_DATA"] == "1"
    }

    static func showModelFullName() -> Bool {
        return ProcessInfo.processInfo.environment["SHOW_MODEL_FULL_NAME"] == "1"
    }

    static func showMoreModels() -> Bool {
        return ProcessInfo.processInfo.environment["SHOW_MORE_MODELS"] == "1"
    }

    /// Walk up to the nearest existing ancestor so volume queries never fail
    /// on a not-yet-created subdirectory.
    private static func nearestExistingDirectory(for path: URL) -> URL {
        var candidate = path
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break } // reached root
            candidate = parent
        }
        return candidate
    }

    static func getFreeDiskSpace(path: URL) -> Int64 {
        let resolvedPath = nearestExistingDirectory(for: path)
        Logger.log("Checking disk space at resolved path: \(resolvedPath.path) (requested: \(path.path))", log: Logger.general)

        // First try the modern API
        do {
            let resourceValues = try resolvedPath.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let freeSpace = resourceValues.volumeAvailableCapacityForImportantUsage {
                Logger.log("Disk free space (modern API): \(freeSpace)", log: Logger.general)
                return freeSpace
            }
            Logger.log("Modern API returned nil for path: \(resolvedPath.path)", log: Logger.general, type: .error)
        } catch {
            Logger.log("Modern API failed for path: \(resolvedPath.path): \(error.localizedDescription)", log: Logger.general, type: .error)
        }

        // Fallback to legacy API
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: resolvedPath.path)
            if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                Logger.log("Disk free space (legacy API): \(freeSpace)", log: Logger.general)
                return freeSpace
            }
            Logger.log("Legacy API returned nil for path: \(resolvedPath.path)", log: Logger.general, type: .error)
        } catch {
            Logger.log("Legacy API failed for path: \(resolvedPath.path): \(error.localizedDescription)", log: Logger.general, type: .error)
        }

        // Last resort: query the home directory volume
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let resourceValues = try home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let freeSpace = resourceValues.volumeAvailableCapacityForImportantUsage {
                Logger.log("Disk free space (home fallback): \(freeSpace)", log: Logger.general)
                return freeSpace
            }
        } catch {
            Logger.log("Home fallback failed: \(error.localizedDescription)", log: Logger.general, type: .error)
        }

        Logger.log("All disk space checks failed, returning -1", log: Logger.general, type: .error)
        return -1
    }

    static func launchApp(appPath: String) throws {
        Logger.log("Launching app", log: Logger.updater)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appPath]
        if isLocalRun() {
            task.environment = ProcessInfo.processInfo.environment
        }
        try task.run()
    }

    static func terminateApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // First try normal termination
            NSApplication.shared.terminate(nil)

            // If that doesn't work, force quit after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Logger.log("Force quitting app", log: Logger.updater)
                exit(0)
            }
        }
    }

    static func isLocalRun() -> Bool {
        return ProcessInfo.processInfo.environment["LOCAL_RUN"] == "1"
    }

    static func getAppLocation() -> String {
        if isLocalRun() {
            return getCurrentProcessPath()
        }
        return "/Applications/\(WhisperClipAppName).app"
    }

    static func getCurrentProcessPath() -> String {
        return Bundle.main.executableURL?.path ?? ""
    }

    static func isDebug() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func copyToClipboard(text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func isWhisperClipActive() -> Bool {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            // Compare by bundle identifier or name
            if let bundleID = frontApp.bundleIdentifier {
                return bundleID.contains(WhisperClipAppName.lowercased())
            }
            if let appName = frontApp.localizedName?.lowercased() {
                return appName.contains(WhisperClipAppName.lowercased())
            }
        }
        return false
    }

    static func paste(text: String) -> Bool {
        if GenericHelper.logSensitiveData() {
            Logger.log("Auto pasting: \(text)", log: Logger.general)
        }

        // Do not paste if WhisperClip is the active app
        if isWhisperClipActive() {
            if GenericHelper.logSensitiveData() {
                Logger.log("Paste skipped: WhisperClip is frontmost app", log: Logger.general)
            }
            return false
        }

        // ⌘V in whichever app is active
        let script = #"""
        tell application "System Events"
            key code 9 using {command down}
        end tell
        """#
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)

        if let err {
            Logger.log("AppleScript error: \(err.description)", log: Logger.general, type: .error)
            return false
        } else {
            if GenericHelper.logSensitiveData() {
                Logger.log("Auto pasted: \(text)", log: Logger.general)
            }
            return true
        }
    }

    static func sendEnter() -> Bool {
        if GenericHelper.logSensitiveData() {
            Logger.log("Auto sending Enter", log: Logger.general)
        }

        // ⌘Enter in whichever app is active
        let script = #"""
        tell application "System Events"
            key code 36
        end tell
        """#
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)

        if let err {
            Logger.log("AppleScript error: \(err.description)", log: Logger.general, type: .error)
            return false
        } else {
            if GenericHelper.logSensitiveData() {
                Logger.log("Auto sent Enter", log: Logger.general)
            }
            return true
        }
    }

    static func waitCondition(condition: () -> Bool, timeout: TimeInterval) -> Bool {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                return false
            }
            sleep(1)
        }
        return true
    }

}
