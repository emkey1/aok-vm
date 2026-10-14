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

import Foundation
import MachO

/// Directory and clipboard sharing settings
struct UTMQemuConfigurationSharing: Codable {
    /// SPICE or virtfs sharing.
    var directoryShareMode: QEMUFileShareMode = .none
    
    /// Sharing should be read only
    var isDirectoryShareReadOnly: Bool = false
    
    /// The directory to share. Not saved.
    var directoryShareUrl: URL?
    
    /// SPICE clipboard sharing.
    var hasClipboardSharing: Bool = false
    
    /// iSH-AOK's /AOK/persist, given to the guest as the VirtFS tag "aokpersist".
    var hasAOKPersist: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case directoryShareMode = "DirectoryShareMode"
        case isDirectoryShareReadOnly = "DirectoryShareReadOnly"
        case hasClipboardSharing = "ClipboardSharing"
        case hasAOKPersist = "AOKPersist"
    }
    
    init() {
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        directoryShareMode = try values.decode(QEMUFileShareMode.self, forKey: .directoryShareMode)
        isDirectoryShareReadOnly = try values.decode(Bool.self, forKey: .isDirectoryShareReadOnly)
        hasClipboardSharing = try values.decode(Bool.self, forKey: .hasClipboardSharing)
        hasAOKPersist = try values.decodeIfPresent(Bool.self, forKey: .hasAOKPersist) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(directoryShareMode, forKey: .directoryShareMode)
        try container.encode(isDirectoryShareReadOnly, forKey: .isDirectoryShareReadOnly)
        try container.encode(hasClipboardSharing, forKey: .hasClipboardSharing)
        try container.encode(hasAOKPersist, forKey: .hasAOKPersist)
    }
}

// MARK: - iSH-AOK's /AOK/persist

extension UTMQemuConfigurationSharing {
    /// The App Group whose container holds iSH-AOK's /AOK/persist (its AOK/persist directory). This app is
    /// signed by the same team and is a member of the group as well, so on a device both apps see one
    /// directory.
    static let aokPersistAppGroup = "group.app.ish.iSH-AOK"
    
    /// That directory, made if iSH-AOK has not run yet. Nil when this build is not in the group. A copy that a
    /// sideloading tool signed again has the group under that tool's name for it, and so has an iSH-AOK the
    /// same tool signed for the same person: the two still share it.
    static var aokPersistUrl: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UTMSignedAppGroups.group(aokPersistAppGroup)) else {
            return nil
        }
        let url = container.appendingPathComponent("AOK", isDirectory: true).appendingPathComponent("persist", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Default construction

extension UTMQemuConfigurationSharing {
    init(forArchitecture architecture: QEMUArchitecture, target: any QEMUTarget) {
        self.init()
        let rawTarget = target.rawValue
        if !architecture.hasAgentSupport {
            hasClipboardSharing = false
        }
        if !architecture.hasSharingSupport {
            directoryShareMode = .none
        }
        // overrides for specific configurations
        if rawTarget.hasPrefix("pc") || rawTarget.hasPrefix("q35") {
            directoryShareMode = .webdav
            hasClipboardSharing = true
        } else if (architecture == .arm || architecture == .aarch64) && (rawTarget.hasPrefix("virt-") || rawTarget == "virt") {
            directoryShareMode = .webdav
            hasClipboardSharing = true
        } else if architecture == .m68k && rawTarget == QEMUTarget_m68k.q800.rawValue {
            directoryShareMode = .virtfs
        } else if [.ppc, .ppc64].contains(architecture) && rawTarget == QEMUTarget_ppc.mac99.rawValue {
            directoryShareMode = .virtfs
        }
    }
}

// MARK: - Conversion of old config format

extension UTMQemuConfigurationSharing {
    init(migrating oldConfig: UTMLegacyQemuConfiguration) {
        self.init()
        if oldConfig.shareDirectoryEnabled {
            directoryShareMode = .webdav
        }
        isDirectoryShareReadOnly = oldConfig.shareDirectoryReadOnly
        hasClipboardSharing = oldConfig.shareClipboardEnabled
    }
}

// MARK: - App Groups as signed

/// AOK VM: the application groups this build is signed with, read from its own code signature. The names in
/// the entitlements file and in Info.plist are only where they start: a sideloading tool (AltStore, SideStore)
/// signs the app again under its user's team and renames each group, AltStore by appending ".TEAMID", and
/// the container of a group the app is not signed with is out of reach.
enum UTMSignedAppGroups {
    static let all: [String] = (entitlements()?["com.apple.security.application-groups"] as? [String]) ?? []

    /// The group this build has for `name`: `name` itself, a tool's rename of it, or `name` when the
    /// signature does not say (unreadable, or not in the group), which is what the app asked for before.
    static func group(_ name: String) -> String {
        if all.contains(name) {
            return name
        }
        return all.first { $0.hasPrefix(name + ".") } ?? all.first { $0.contains(name) } ?? name
    }

    private static func entitlements() -> [String: Any]? {
        guard let data = entitlementsData() else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// The executable's entitlements: a section of it in the simulator, a blob of its code signature on a
    /// device.
    private static func entitlementsData() -> Data? {
        guard let header = mainHeader() else {
            return nil
        }
        var size: UInt = 0
        if let section = getsectiondata(header, "__TEXT", "__entitlements", &size), size > 0 {
            return Data(bytes: section, count: Int(size))
        }
        guard let signature = codeSignature(header) else {
            return nil
        }
        return entitlementsBlob(in: signature)
    }

    private static func mainHeader() -> UnsafePointer<mach_header_64>? {
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        var index: UInt32 = 0
        for i in 0..<_dyld_image_count() {
            if let name = _dyld_get_image_name(i),
               URL(fileURLWithPath: String(cString: name)).resolvingSymlinksInPath().path == executable {
                index = i
                break
            }
        }
        guard let header = _dyld_get_image_header(index), header.pointee.magic == 0xfeedfacf /* MH_MAGIC_64 */ else {
            return nil
        }
        return UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
    }

    /// The code signature's bytes, from the executable's file: LC_CODE_SIGNATURE says where in its slice.
    private static func codeSignature(_ header: UnsafePointer<mach_header_64>) -> [UInt8]? {
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        var signature: linkedit_data_command?
        for _ in 0..<header.pointee.ncmds {
            let load = command.loadUnaligned(as: load_command.self)
            if load.cmd == 0x1d /* LC_CODE_SIGNATURE */ {
                signature = command.loadUnaligned(as: linkedit_data_command.self)
                break
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        guard let signature, let url = Bundle.main.executableURL,
              let file = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? file.close()
        }
        guard let slice = sliceOffset(file, header.pointee) else {
            return nil
        }
        try? file.seek(toOffset: slice + UInt64(signature.dataoff))
        guard let data = try? file.read(upToCount: Int(signature.datasize)), data.count == Int(signature.datasize) else {
            return nil
        }
        return [UInt8](data)
    }

    /// Where this architecture's slice starts: 0 in a thin file.
    private static func sliceOffset(_ file: FileHandle, _ header: mach_header_64) -> UInt64? {
        try? file.seek(toOffset: 0)
        guard let start = try? file.read(upToCount: 8), start.count == 8 else {
            return nil
        }
        let bytes = [UInt8](start)
        let magic = bigEndian32(bytes, 0)
        guard magic == 0xcafebabe || magic == 0xcafebabf else { // FAT_MAGIC, FAT_MAGIC_64
            return 0
        }
        let entry = magic == 0xcafebabe ? 20 : 32 // fat_arch, fat_arch_64
        let count = Int(bigEndian32(bytes, 4) ?? 0)
        guard let table = try? file.read(upToCount: count * entry), table.count == count * entry else {
            return nil
        }
        let arches = [UInt8](table)
        for i in 0..<count {
            let at = i * entry
            guard bigEndian32(arches, at).map({ cpu_type_t(bitPattern: $0) }) == header.cputype else {
                continue
            }
            if magic == 0xcafebabe {
                return bigEndian32(arches, at + 8).map(UInt64.init)
            }
            guard let high = bigEndian32(arches, at + 8), let low = bigEndian32(arches, at + 12) else {
                return nil
            }
            return UInt64(high) << 32 | UInt64(low)
        }
        return nil
    }

    /// The entitlements (XML) in a code signature: a SuperBlob whose index points at its blobs, one of them
    /// the entitlements blob. Big-endian throughout.
    private static func entitlementsBlob(in signature: [UInt8]) -> Data? {
        guard bigEndian32(signature, 0) == 0xfade0cc0, let count = bigEndian32(signature, 8) else {
            return nil
        }
        for i in 0..<Int(count) {
            guard let offset = bigEndian32(signature, 12 + i * 8 + 4).map(Int.init) else {
                return nil
            }
            guard bigEndian32(signature, offset) == 0xfade7171,
                  let length = bigEndian32(signature, offset + 4).map(Int.init),
                  length >= 8, offset + length <= signature.count else {
                continue
            }
            return Data(signature[(offset + 8)..<(offset + length)])
        }
        return nil
    }

    private static func bigEndian32(_ bytes: [UInt8], _ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= bytes.count else {
            return nil
        }
        return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }
}
