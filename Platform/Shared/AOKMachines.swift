//
// AOK VM's own machines: iSH-AOK's Alpine and Devuan roots as machines of their own, for the four
// architectures iSH-AOK has, and ReactOS (aok/images and aok/reactos in this repository). The app carries
// some (Resources/AOKMachines) and puts them in the list on its first start; the rest are downloads,
// checked against the SHA-256 the list gives. The list is AOKMachines/machines.json, or a newer one from
// the address it names, when that can be fetched.
//

import SwiftUI

struct AOKMachine: Codable, Identifiable, Hashable {
    let id: String
    /// The machine's name, as its bundle has it.
    let name: String
    let architecture: String
    let summary: String
    /// The zip: in the app's AOKMachines, or under the list's baseURL.
    let file: String
    let size: Int64
    let sha256: String
}

struct AOKMachineList: Codable {
    let version: Int
    /// Where a newer list is.
    let indexURL: URL?
    /// Where the zips that the app does not carry are.
    let baseURL: URL
    let machines: [AOKMachine]
}

@MainActor
final class AOKMachineCatalog: ObservableObject {
    static let shared = AOKMachineCatalog()

    @Published private(set) var list: AOKMachineList?

    private static let installedKey = "AOKBundledMachinesInstalled"

    private static var resources: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("AOKMachines", isDirectory: true)
    }

    init() {
        if let url = Self.resources?.appendingPathComponent("machines.json"),
           let data = try? Data(contentsOf: url) {
            list = try? JSONDecoder().decode(AOKMachineList.self, from: data)
        }
    }

    /// A newer list, where this one says, if there is one.
    func refresh() async {
        guard let url = list?.indexURL else {
            return
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let newer = try? JSONDecoder().decode(AOKMachineList.self, from: data),
              newer.version >= (list?.version ?? 0) else {
            return
        }
        list = newer
    }

    /// The machine's zip in the app, if the app carries it.
    func bundledZip(for machine: AOKMachine) -> URL? {
        guard let url = Self.resources?.appendingPathComponent(machine.file),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func isInstalled(_ machine: AOKMachine, in data: UTMData) -> Bool {
        data.virtualMachines.contains { $0.detailsTitleLabel == machine.name }
    }

    /// Into the list: unpacked from the app, or downloaded.
    func install(_ machine: AOKMachine, data: UTMData) {
        if let zip = bundledZip(for: machine) {
            data.busyWorkAsync {
                try await data.installUTMZip(at: zip)
            }
        } else if let base = list?.baseURL {
            data.downloadUTMZip(from: base.appendingPathComponent(machine.file), sha256: machine.sha256)
        }
    }

    /// On the first start: the machines the app carries, each once. One its user has removed since is not
    /// put back, and one already in the list (by name) is left alone.
    func installBundledOnce(data: UTMData) async {
        var done = Set(UserDefaults.standard.stringArray(forKey: Self.installedKey) ?? [])
        for machine in list?.machines ?? [] where !done.contains(machine.id) {
            guard let zip = bundledZip(for: machine) else {
                continue
            }
            if !isInstalled(machine, in: data) {
                do {
                    try await data.installUTMZip(at: zip)
                } catch {
                    logger.error("AOK VM: could not add \(machine.name): \(error)")
                    continue
                }
            }
            done.insert(machine.id)
            UserDefaults.standard.set(Array(done), forKey: Self.installedKey)
        }
    }
}

/// "Get a Machine": AOK VM's machines, those the app carries first.
struct AOKMachinesView: View {
    @EnvironmentObject private var data: UTMData
    @ObservedObject private var catalog = AOKMachineCatalog.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                let machines = catalog.list?.machines ?? []
                Section {
                    ForEach(machines.filter { catalog.bundledZip(for: $0) != nil }) { row($0, bundled: true) }
                } header: {
                    Text("Included with AOK VM")
                }
                Section {
                    ForEach(machines.filter { catalog.bundledZip(for: $0) == nil }) { row($0, bundled: false) }
                } header: {
                    Text("Download")
                } footer: {
                    Text("Each is iSH-AOK's own root file system as a machine of its own, kept small: in it, `aok-update` brings the /AOK/tools scripts, which add a desktop and the rest when you want them.")
                }
            }
            .navigationTitle("Get a Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await catalog.refresh()
        }
    }

    private func row(_ machine: AOKMachine, bundled: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(machine.name)
                    .font(.headline)
                Text(machine.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if catalog.isInstalled(machine, in: data) {
                Text("Added")
                    .foregroundColor(.secondary)
            } else {
                Button {
                    // Once the sheets are gone: an error (a download that fails at once) is an alert,
                    // which a sheet still closing would swallow.
                    data.showNewVMSheet = false
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        catalog.install(machine, data: data)
                    }
                } label: {
                    if bundled {
                        Text("Add")
                    } else {
                        Text("Get · \(ByteCountFormatter.string(fromByteCount: machine.size, countStyle: .file))")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
