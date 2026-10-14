//
// Copyright © 2022 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import CryptoKit
import Foundation
import Logging
import os
import ZIPFoundation

/// Downloads a VM and creates a pending VM placeholder.
class UTMDownloadVMTask: UTMDownloadTask {
    /// AOK VM: the SHA-256 the download must have (AOK VM's machine list gives one), lower-case hex.
    private let expectedSHA256: String?
    
    init(for url: URL, sha256: String? = nil) {
        self.expectedSHA256 = sha256?.lowercased()
        super.init(for: url, named: UTMDownloadVMTask.name(for: url))
    }
    
    /// AOK VM: a machine in a zip that is already here (one the app carries) into `folder`, unpacked as a
    /// download is. Returns the .utm.
    static func unpack(zip: URL, into folder: URL) throws -> URL {
        try UTMDownloadVMTask(for: zip).partialUnzipOnlyUtmVM(zipFileURL: zip, destinationFolder: folder, fileManager: FileManager.default)
    }
    
    /// AOK VM: the machine at `bundle` made to fit this device, its memory and CPUs lowered, never raised.
    ///
    /// Memory: the most that UTM's own estimate (VMConfigSystemView: the guest's memory, twice the
    /// translation cache, which is a quarter of it, and 128 MB) keeps under 90% of what iOS lets this app
    /// have, in steps of 64 MB and not below 256 MB. A machine that would use 1 GB takes 1.7 GB by that
    /// estimate: too much for a device with 2 GB, which gets 512 MB. (Only when the cache is the default
    /// quarter: a machine that names its own is left alone.)
    ///
    /// CPUs: each is a host thread under the AOK engine, so one of the cores iOS reports stays the app's
    /// (its screen, input and disk): a dual-core device (an A9) gets one, and anything with three or more
    /// keeps the two the machines have. Not below one.
    static func fitToDevice(_ bundle: URL) {
        let plist = bundle.appendingPathComponent("config.plist")
        guard let data = try? Data(contentsOf: plist),
              var config = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any],
              var system = config["System"] as? [String: Any] else {
            return
        }
        var changed = false
        if let memory = system["MemorySize"] as? Int, ((system["JITCacheSize"] as? Int) ?? 0) == 0 {
            var available = ProcessInfo.processInfo.physicalMemory
            #if os(iOS) || os(visionOS)
            let left = UInt64(os_proc_available_memory())
            if left > 0 {
                available = min(available, left)
            }
            #endif
            let mib = Double(available) / 1048576
            let fits = max(256, (Int((0.9 * mib - 128) / 1.5) / 64) * 64)
            if fits < memory {
                logger.info("AOK VM: \(bundle.lastPathComponent): \(memory) MB of memory is more than this device has room for; \(fits) MB")
                system["MemorySize"] = fits
                changed = true
            }
        }
        // (0 is UTM's "default", which is not ours to change)
        if let cpus = system["CPUCount"] as? Int, cpus > 0 {
            let fits = max(1, min(cpus, ProcessInfo.processInfo.activeProcessorCount - 1))
            if fits < cpus {
                logger.info("AOK VM: \(bundle.lastPathComponent): \(cpus) CPUs leave this device's \(ProcessInfo.processInfo.activeProcessorCount) cores none for the app; \(fits)")
                system["CPUCount"] = fits
                changed = true
            }
        }
        guard changed else {
            return
        }
        config["System"] = system
        if let out = try? PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0) {
            try? out.write(to: plist)
        }
    }
    
    /// The file's SHA-256, lower-case hex, read a megabyte at a time.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    static private func name(for url: URL) -> String {
        /// try to detect the filename from the URL
        let filename = url.lastPathComponent
        var nameWithoutZIP = "UTM Virtual Machine"
        /// Try to get the start index of the `.zip` part of the filename
        if let index = filename.range(of: ".zip", options: [])?.lowerBound {
            nameWithoutZIP = String(filename[..<index])
        }
        return nameWithoutZIP
    }
    
    override func processCompletedDownload(at location: URL, response: URLResponse?) async throws -> any UTMVirtualMachine {
        let tempDir = fileManager.temporaryDirectory
        let originalFilename = url.lastPathComponent
        let downloadedZip = tempDir.appendingPathComponent(originalFilename)
        var fileURL: URL? = nil
        do {
            if let expected = expectedSHA256, try Self.sha256(of: location) != expected {
                throw ChecksumMismatchError()
            }
            if fileManager.fileExists(atPath: downloadedZip.path) {
                try fileManager.removeItem(at: downloadedZip)
            }
            try fileManager.moveItem(at: location, to: downloadedZip)
            let utmURL = try partialUnzipOnlyUtmVM(zipFileURL: downloadedZip, destinationFolder: UTMData.defaultStorageUrl, fileManager: fileManager)
            /// set the url so we know, if it fails after this step the UTM in the ZIP is corrupted
            fileURL = utmURL
            /// AOK VM: one of its own machines (it comes with a checksum) is sized to this device
            if expectedSHA256 != nil {
                Self.fitToDevice(utmURL)
            }
            /// remove the downloaded ZIP file
            try fileManager.removeItem(at: downloadedZip)
            /// load the downloaded VM into the UI
            let vm = try await VMData(url: utmURL)
            return await vm.wrapped!
        } catch {
            logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            if let fileURL = fileURL {
                /// remove imported UTM, as it is corrupted
                try? fileManager.removeItem(at: fileURL)
            } else {
                /// failed earlier
                try? fileManager.removeItem(at: downloadedZip)
            }
            throw error
        }
    }
    
    private func partialUnzipOnlyUtmVM(zipFileURL: URL, destinationFolder: URL, fileManager: FileManager) throws -> URL {
        let utmFileEnding = ".utm"
        let utmDirectoryEnding = "\(utmFileEnding)/"
        if let archive = Archive(url: zipFileURL, accessMode: .read),
           /// find the UTM directory and its contents
           let utmFolderInZip = archive.first(where: { $0.path.hasSuffix(utmDirectoryEnding) }) {
            /// get the UTM package filename
            let originalFileName = URL(fileURLWithPath: utmFolderInZip.path).lastPathComponent
            var destinationUtmDirectory = originalFileName
            /// check if the UTM already exists
            var duplicateIndex = 2
            while fileManager.fileExists(atPath: destinationFolder.appendingPathComponent(destinationUtmDirectory).path) {
                destinationUtmDirectory = originalFileName.replacingOccurrences(of: utmFileEnding, with: " (\(duplicateIndex))\(utmFileEnding)")
                duplicateIndex += 1
            }
            /// got destination folder name
            let destinationURL = destinationFolder.appendingPathComponent(destinationUtmDirectory, isDirectory: true)
            /// create the .utm directory
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
            do {
                /// get and extract all files contained in the UTM directory, except the `__MACOSX` folder
                let containedFiles = archive.filter({ $0.path.hasPrefix(utmFolderInZip.path) && !$0.path.hasSuffix(utmDirectoryEnding) && !$0.path.contains("__MACOSX") })
                for file in containedFiles {
                    /// we never store a symlink in a package, and a link target that survives a containment
                    /// check can still be resolved outside of the package when it is written through later
                    guard file.type != .symlink else {
                        throw UnzipUnsafePathError()
                    }
                    let relativePath = String(file.path.dropFirst(utmFolderInZip.path.count))
                    let isDirectory = file.path.hasSuffix("/")
                    let fileURL = try containedDestination(for: relativePath, in: destinationURL, isDirectory: isDirectory)
                    _ = try archive.extract(file, to: fileURL, skipCRC32: true)
                }
            } catch {
                /// a partially extracted package would still be picked up as a VM by the library
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }
            return destinationURL
        } else {
            throw UnzipNoUTMFileError()
        }
    }
    
    /// Resolve an archive entry's relative path inside `destinationFolder` and reject any escape.
    ///
    /// A crafted archive can name an entry `some.utm/../../elsewhere`. `appendingPathComponent()` does not
    /// resolve `..`, so the traversal would only be resolved by the filesystem at write time.
    private func containedDestination(for relativePath: String, in destinationFolder: URL, isDirectory: Bool) throws -> URL {
        let candidate = destinationFolder.appendingPathComponent(relativePath, isDirectory: isDirectory)
        /// POSIX `fopen()` collapses repeated separators before resolving `..`, so an entry named `/../elsewhere`
        /// would otherwise standardize to a contained path here but escape once written. Collapse them first.
        var path = candidate.path
        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }
        let resolved = URL(fileURLWithPath: path, isDirectory: isDirectory).standardized
        let root = URL(fileURLWithPath: destinationFolder.path, isDirectory: true).standardized
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw UnzipUnsafePathError()
        }
        return resolved
    }
    
    private class UnzipUnsafePathError: LocalizedError {
        var errorDescription: String? {
            NSLocalizedString("The downloaded ZIP archive contains an invalid path.", comment: "Error shown when importing a ZIP file from web that contains an entry pointing outside of the virtual machine directory.")
        }
    }
    
    private class UnzipNoUTMFileError: LocalizedError {
        var errorDescription: String? {
            NSLocalizedString("There is no UTM file in the downloaded ZIP archive.", comment: "Error shown when importing a ZIP file from web that doesn't contain a UTM Virtual Machine.")
        }
    }
    
    private class CreateUTMFailed: LocalizedError {
        var errorDescription: String? {
            NSLocalizedString("Failed to parse the downloaded VM.", comment: "UTMDownloadVMTask")
        }
    }
}

/// AOK VM: a download whose SHA-256 is not the one its machine list gives.
struct ChecksumMismatchError: LocalizedError {
    var errorDescription: String? {
        NSLocalizedString("The download is not the machine it should be (its SHA-256 differs), so nothing was added. Try again.", comment: "UTMDownloadVMTask")
    }
}
