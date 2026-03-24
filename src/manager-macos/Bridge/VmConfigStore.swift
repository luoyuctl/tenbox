import Foundation

class VmConfigStore {

    static let appSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TenBox")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let vmsDirectory: URL = {
        let dir = appSupportDirectory.appendingPathComponent("vms")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: - Paths

    func vmDirectory(for vmId: String) -> URL {
        Self.vmsDirectory.appendingPathComponent(vmId)
    }

    func configURL(for vmId: String) -> URL {
        vmDirectory(for: vmId).appendingPathComponent("config.json")
    }

    // MARK: - Read / Write

    func readConfig(vmId: String) -> VmConfig? {
        let url = configURL(for: vmId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(VmConfig.self, from: data)
    }

    @discardableResult
    func writeConfig(vmId: String, config: VmConfig) -> Bool {
        guard let data = try? encoder.encode(config) else { return false }
        return FileManager.default.createFile(atPath: configURL(for: vmId).path, contents: data)
    }

    // MARK: - List

    func listVms() -> [(id: String, config: VmConfig)] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: Self.vmsDirectory.path) else { return [] }
        var result: [(id: String, config: VmConfig)] = []
        for item in items {
            guard let config = readConfig(vmId: item) else { continue }
            result.append((id: item, config: config))
        }
        return result
    }

    // MARK: - Create

    @discardableResult
    func createVm(from createConfig: VmCreateConfig) -> String? {
        let vmId = UUID().uuidString
        let vmDir = vmDirectory(for: vmId)
        let fm = FileManager.default

        guard (try? fm.createDirectory(at: vmDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }

        func copyFile(_ srcPath: String) -> String {
            guard !srcPath.isEmpty else { return "" }
            let fileName = (srcPath as NSString).lastPathComponent
            let dest = vmDir.appendingPathComponent(fileName).path
            do {
                try fm.copyItem(atPath: srcPath, toPath: dest)
                return dest
            } catch {
                NSLog("Failed to copy %@ -> %@: %@", srcPath, dest, error.localizedDescription)
                return srcPath
            }
        }

        let kernelPath = createConfig.kernelPath.isEmpty ? "" : copyFile(createConfig.kernelPath)
        let initrdPath = createConfig.initrdPath.isEmpty ? "" : copyFile(createConfig.initrdPath)
        let diskPath = createConfig.diskPath.isEmpty ? "" : copyFile(createConfig.diskPath)

        let config = VmConfig(
            name: createConfig.name,
            kernelPath: kernelPath,
            initrdPath: initrdPath,
            diskPath: diskPath,
            memoryMb: createConfig.memoryMb,
            cpuCount: createConfig.cpuCount,
            state: "stopped",
            netEnabled: createConfig.netEnabled,
            debugMode: createConfig.debugMode,
            displayScale: 1
        )

        guard writeConfig(vmId: vmId, config: config) else { return nil }
        return vmId
    }

    // MARK: - Edit

    @discardableResult
    func editVm(id: String, name: String, memoryMb: Int, cpuCount: Int,
                netEnabled: Bool, debugMode: Bool) -> Bool {
        guard var config = readConfig(vmId: id) else { return false }
        config.name = name
        config.memoryMb = memoryMb
        config.cpuCount = cpuCount
        config.netEnabled = netEnabled
        config.debugMode = debugMode
        return writeConfig(vmId: id, config: config)
    }

    // MARK: - Delete

    @discardableResult
    func deleteVm(id: String) -> Bool {
        return (try? FileManager.default.removeItem(at: vmDirectory(for: id))) != nil
    }

    // MARK: - State

    @discardableResult
    func updateState(vmId: String, state: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        config.state = state
        return writeConfig(vmId: vmId, config: config)
    }

    // MARK: - Display Scale

    @discardableResult
    func setDisplayScale(vmId: String, scale: Int) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        config.displayScale = max(1, min(2, scale))
        return writeConfig(vmId: vmId, config: config)
    }

    // MARK: - Shared Folders

    @discardableResult
    func addSharedFolder(_ folder: SharedFolder, toVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        if config.sharedFolders.contains(where: { $0.tag == folder.tag }) { return false }
        config.sharedFolders.append(SharedFolderConfig.from(folder))
        return writeConfig(vmId: vmId, config: config)
    }

    @discardableResult
    func removeSharedFolder(tag: String, fromVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        guard let idx = config.sharedFolders.firstIndex(where: { $0.tag == tag }) else { return false }
        config.sharedFolders.remove(at: idx)
        return writeConfig(vmId: vmId, config: config)
    }

    @discardableResult
    func setSharedFolders(_ folders: [SharedFolder], forVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        config.sharedFolders = folders.map { SharedFolderConfig.from($0) }
        return writeConfig(vmId: vmId, config: config)
    }

    // MARK: - Port Forwards

    @discardableResult
    func addPortForward(_ pf: PortForward, toVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        if config.portForwards.contains(where: { $0.hostPort == pf.hostPort }) { return false }
        config.portForwards.append(PortForwardConfig.from(pf))
        return writeConfig(vmId: vmId, config: config)
    }

    @discardableResult
    func removePortForward(hostPort: UInt16, fromVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        guard let idx = config.portForwards.firstIndex(where: { $0.hostPort == hostPort }) else { return false }
        config.portForwards.remove(at: idx)
        return writeConfig(vmId: vmId, config: config)
    }

    // MARK: - Guest Forwards

    @discardableResult
    func addGuestForward(_ gf: GuestForward, toVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        if config.guestForwards.contains(where: { $0.guestIp == gf.guestIp && $0.guestPort == gf.guestPort }) {
            return false
        }
        config.guestForwards.append(GuestForwardConfig.from(gf))
        return writeConfig(vmId: vmId, config: config)
    }

    @discardableResult
    func removeGuestForward(guestIp: String, guestPort: UInt16, fromVm vmId: String) -> Bool {
        guard var config = readConfig(vmId: vmId) else { return false }
        guard let idx = config.guestForwards.firstIndex(where: {
            $0.guestIp == guestIp && $0.guestPort == guestPort
        }) else { return false }
        config.guestForwards.remove(at: idx)
        return writeConfig(vmId: vmId, config: config)
    }
}
