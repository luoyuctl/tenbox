import SwiftUI

private let hostMaxCpus = ProcessInfo.processInfo.activeProcessorCount
private let hostMaxMemoryGb = max(1, Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)))

// MARK: - Create VM Dialog (Wizard)

struct CreateVmDialog: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = CreateVmViewModel()

    var body: some View {
        VStack(spacing: 0) {
            switch vm.page {
            case .selectImage:
                SelectImagePage(vm: vm, dismiss: dismiss)
            case .downloading:
                DownloadingPage(vm: vm)
            case .confirm:
                ConfirmPage(vm: vm, appState: appState, dismiss: dismiss)
            }
        }
        .frame(width: 560, height: 500)
        .onAppear {
            vm.loadCachedImages()
            vm.fetchSources()
        }
    }
}

// MARK: - Pages

private struct SelectImagePage: View {
    @ObservedObject var vm: CreateVmViewModel
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            Text("Create New VM")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HStack {
                Text("Source:")
                    .frame(width: 56, alignment: .trailing)
                Picker("", selection: $vm.selectedSourceIndex) {
                    if vm.sources.isEmpty {
                        Text("Loading...").tag(-1)
                    }
                    ForEach(Array(vm.sources.enumerated()), id: \.offset) { i, src in
                        Text(src.name).tag(i)
                    }
                }
                .labelsHidden()
                .disabled(vm.sources.isEmpty)
                .onChange(of: vm.selectedSourceIndex) {
                    vm.onSourceChanged()
                }
                Button {
                    vm.refreshOnlineImages()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isLoadingOnline || vm.sources.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            List(selection: $vm.selectedImageId) {
                if !vm.cachedImages.isEmpty {
                    Section("Cached") {
                        ForEach(vm.cachedImages) { img in
                            ImageRow(image: img, isCached: true)
                                .tag(img.id + "||cached")
                        }
                    }
                }
                Section("Online") {
                    if vm.isLoadingSources || vm.isLoadingOnline {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(vm.filteredOnlineImages) { img in
                        ImageRow(image: img, isCached: false)
                            .tag(img.id + "||online")
                    }
                }
            }
            .listStyle(.bordered)
            .padding(.horizontal, 16)

            if let img = vm.resolvedSelectedImage {
                Text(img.description.isEmpty ? "No description" : img.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }

            if !vm.errorMessage.isEmpty {
                Text(vm.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            HStack {
                Button("Delete Cache") {
                    vm.deleteSelectedCache()
                }
                .disabled(!vm.canDeleteCache)

                Spacer()

                Button("Local Image...") {
                    vm.browseLocalImage()
                }

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Next") {
                    vm.goNext()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.selectedImageId == nil)
            }
            .padding(16)
        }
    }
}

private struct DownloadingPage: View {
    @ObservedObject var vm: CreateVmViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Downloading Image")
                .font(.title2)
                .fontWeight(.semibold)

            ProgressView(value: vm.downloadProgress, total: 1.0)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)

            Text(vm.downloadStatusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    vm.cancelDownload()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
    }
}

private struct ConfirmPage: View {
    @ObservedObject var vm: CreateVmViewModel
    let appState: AppState
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            Text("Create New VM")
                .font(.title2)
                .fontWeight(.semibold)
                .padding()

            Form {
                Section("General") {
                    TextField("Name", text: $vm.vmName)
                    Stepper("CPUs: \(vm.cpuCount)", value: $vm.cpuCount, in: 1...hostMaxCpus)
                    Stepper("Memory: \(vm.memoryGb) GB", value: $vm.memoryGb, in: 1...hostMaxMemoryGb)
                }

                if let img = vm.selectedImage {
                    Section("Image") {
                        LabeledContent("Image") {
                            Text(img.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            if !vm.errorMessage.isEmpty {
                Text(vm.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Divider()

            HStack {
                Button("Back") {
                    vm.goBack()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    vm.createVm(appState: appState)
                    if vm.created {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.vmName.isEmpty)
            }
            .padding(16)
        }
    }
}

// MARK: - Image row

private struct ImageRow: View {
    let image: ImageEntry
    let isCached: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(image.displayName)
                    .lineLimit(1)
                if !image.description.isEmpty {
                    Text(image.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if image.totalSize > 0 {
                Text(formatSize(image.totalSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ViewModel

enum CreateVmPage {
    case selectImage
    case downloading
    case confirm
}

@MainActor
class CreateVmViewModel: ObservableObject {
    @Published var page: CreateVmPage = .selectImage
    @Published var sources: [ImageSource] = []
    @Published var selectedSourceIndex: Int = -1
    @Published var isLoadingSources = false
    @Published var isLoadingOnline = false
    @Published var cachedImages: [ImageEntry] = []
    @Published var onlineImages: [ImageEntry] = []
    @Published var selectedImageId: String?
    @Published var errorMessage = ""

    // Download state
    @Published var downloadProgress: Double = 0
    @Published var downloadStatusText = ""
    private var downloadCancelled = false
    private var downloadTask: Task<Void, Never>?

    // Confirm state
    @Published var selectedImage: ImageEntry?
    @Published var isLocalImage = false
    @Published var localImageDir = ""
    @Published var vmName = ""
    @Published var memoryGb: Int = min(4, hostMaxMemoryGb)
    @Published var cpuCount: Int = min(4, hostMaxCpus)
    @Published var created = false

    private let service = ImageSourceService.shared

    var filteredOnlineImages: [ImageEntry] {
        let cachedIds = Set(cachedImages.map { "\($0.id)-\($0.version)" })
        return onlineImages.filter { !cachedIds.contains("\($0.id)-\($0.version)") }
    }

    var resolvedSelectedImage: ImageEntry? {
        guard let selectedId = selectedImageId else { return nil }
        let parts = selectedId.components(separatedBy: "||")
        guard parts.count == 2 else { return nil }
        let imageId = parts[0]
        let source = parts[1]
        if source == "cached" {
            return cachedImages.first { $0.id == imageId }
        } else {
            return onlineImages.first { $0.id == imageId }
                ?? cachedImages.first { $0.id == imageId }
        }
    }

    var canDeleteCache: Bool {
        guard let selectedId = selectedImageId else { return false }
        return selectedId.hasSuffix("||cached")
    }

    // MARK: - Actions

    func loadCachedImages() {
        cachedImages = service.getCachedImages()
    }

    func fetchSources() {
        guard !isLoadingSources else { return }
        isLoadingSources = true
        errorMessage = ""

        Task {
            do {
                let fetched = try await service.fetchSources()
                sources = fetched
                if !fetched.isEmpty && selectedSourceIndex < 0 {
                    selectedSourceIndex = 0
                    fetchOnlineImages()
                }
            } catch {
                errorMessage = "Failed to load sources: \(error.localizedDescription)"
            }
            isLoadingSources = false
        }
    }

    func onSourceChanged() {
        onlineImages = []
        selectedImageId = nil
        errorMessage = ""
        fetchOnlineImages()
    }

    func refreshOnlineImages() {
        onlineImages = []
        selectedImageId = nil
        errorMessage = ""
        fetchOnlineImages()
    }

    private func fetchOnlineImages() {
        guard selectedSourceIndex >= 0, selectedSourceIndex < sources.count else { return }
        guard !isLoadingOnline else { return }
        isLoadingOnline = true
        errorMessage = ""

        let url = sources[selectedSourceIndex].url
        Task {
            do {
                let images = try await service.fetchImages(from: url)
                let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                onlineImages = service.filterImages(images, appVersion: appVersion)
            } catch {
                errorMessage = "Failed to load images: \(error.localizedDescription)"
            }
            isLoadingOnline = false
        }
    }

    func deleteSelectedCache() {
        guard let img = resolvedSelectedImage else { return }
        do {
            try service.deleteImageCache(for: img)
            loadCachedImages()
            selectedImageId = nil
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func browseLocalImage() {
        let panel = NSOpenPanel()
        panel.title = "Select Image Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let dirPath = url.path
        let fm = FileManager.default
        var kernel = "", initrd = "", disk = ""

        if let items = try? fm.contentsOfDirectory(atPath: dirPath) {
            for name in items {
                let fullPath = (dirPath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

                if name == "vmlinuz" || name.hasPrefix("vmlinuz") || name.hasPrefix("Image") {
                    if kernel.isEmpty { kernel = name }
                } else if name.hasPrefix("initrd") || name.hasPrefix("initramfs") || name.hasSuffix(".cpio.gz") {
                    if initrd.isEmpty { initrd = name }
                } else if name.hasSuffix(".qcow2") {
                    if disk.isEmpty { disk = name }
                }
            }
        }

        if disk.isEmpty && kernel.isEmpty {
            errorMessage = "No valid image files found (vmlinuz or .qcow2)"
            return
        }

        var files: [ImageFile] = []
        if !kernel.isEmpty { files.append(ImageFile(name: kernel)) }
        if !initrd.isEmpty { files.append(ImageFile(name: initrd)) }
        if !disk.isEmpty { files.append(ImageFile(name: disk)) }

        let dirName = url.lastPathComponent
        let localEntry = ImageEntry(id: dirName, displayName: dirName, files: files)
        selectedImage = localEntry
        isLocalImage = true
        localImageDir = dirPath
        vmName = nextVmName(for: dirName)
        page = .confirm
    }

    func goNext() {
        guard let img = resolvedSelectedImage else { return }
        selectedImage = img
        isLocalImage = false
        localImageDir = ""
        vmName = nextVmName(for: img.id)

        if service.isImageCached(img) {
            page = .confirm
        } else {
            startDownload(img)
        }
    }

    func goBack() {
        page = .selectImage
        isLocalImage = false
        localImageDir = ""
        errorMessage = ""
    }

    // MARK: - Download

    private func startDownload(_ entry: ImageEntry) {
        page = .downloading
        downloadCancelled = false
        downloadProgress = 0
        downloadStatusText = "Preparing..."
        errorMessage = ""

        downloadTask = Task {
            do {
                try await service.downloadImage(entry, progress: { [weak self] fileIdx, totalFiles, fileName, downloaded, total in
                    Task { @MainActor in
                        guard let self = self else { return }
                        let fileProgress = total > 0 ? Double(downloaded) / Double(total) : 0
                        self.downloadProgress = fileProgress

                        var text = "File \(fileIdx + 1)/\(totalFiles): \(fileName)"
                        text += "\n\(Int(fileProgress * 100))%"
                        if total > 0 {
                            text += "  \(formatSize(downloaded)) / \(formatSize(total))"
                        }
                        self.downloadStatusText = text
                    }
                }, isCancelled: { [weak self] in
                    self?.downloadCancelled ?? true
                })

                loadCachedImages()
                page = .confirm
            } catch {
                if !downloadCancelled {
                    errorMessage = error.localizedDescription
                }
                page = .selectImage
            }
        }
    }

    func cancelDownload() {
        downloadCancelled = true
        downloadTask?.cancel()
        page = .selectImage
    }

    // MARK: - Create VM

    func createVm(appState: AppState) {
        guard let img = selectedImage else { return }
        errorMessage = ""

        let sourceDir: String
        if isLocalImage {
            sourceDir = localImageDir
        } else {
            sourceDir = service.imageCacheDir(for: img)
        }

        var kernelPath = "", initrdPath = "", diskPath = ""
        for file in img.files {
            let path = (sourceDir as NSString).appendingPathComponent(file.name)
            if file.name == "vmlinuz" || file.name.hasPrefix("vmlinuz") || file.name.hasPrefix("Image") {
                kernelPath = path
            } else if file.name.hasPrefix("initrd") || file.name.hasPrefix("initramfs") {
                initrdPath = path
            } else if file.name.hasSuffix(".qcow2") || file.name.contains("rootfs") {
                diskPath = path
            }
        }

        let config = VmCreateConfig(
            name: vmName,
            kernelPath: kernelPath,
            initrdPath: initrdPath,
            diskPath: diskPath,
            memoryMb: memoryGb * 1024,
            cpuCount: cpuCount,
            netEnabled: true,
            sourceDir: sourceDir
        )
        appState.createVm(config: config)
        created = true
    }

    // MARK: - Helpers

    private func nextVmName(for imageId: String) -> String {
        let prefix = imageId + "-"
        var maxN = 0
        for vm in (try? ImageSourceService.shared.existingVmNames()) ?? [] {
            if vm.hasPrefix(prefix), let n = Int(vm.dropFirst(prefix.count)) {
                maxN = max(maxN, n)
            }
        }
        return prefix + "\(maxN + 1)"
    }
}

// MARK: - Helpers

private func formatSize(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024 && unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    if unit == 0 {
        return "\(bytes) \(units[0])"
    }
    return String(format: "%.1f %@", value, units[unit])
}

// MARK: - Edit VM Dialog (unchanged)

struct EditVmDialog: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let vm: VmInfo

    @State private var name: String
    @State private var memoryGb: Int
    @State private var cpuCount: Int

    init(vm: VmInfo) {
        self.vm = vm
        _name = State(initialValue: vm.name)
        _memoryGb = State(initialValue: max(1, vm.memoryMb / 1024))
        _cpuCount = State(initialValue: vm.cpuCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit VM")
                .font(.title2)
                .fontWeight(.semibold)
                .padding()

            Form {
                Section("General") {
                    TextField("Name", text: $name)
                    Stepper("CPUs: \(cpuCount)", value: $cpuCount, in: 1...hostMaxCpus)
                    Stepper("Memory: \(memoryGb) GB", value: $memoryGb, in: 1...hostMaxMemoryGb)
                }

                Section("Paths (read-only)") {
                    LabeledContent("Kernel") {
                        Text(vm.kernelPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Disk") {
                        Text(vm.diskPath.isEmpty ? "None" : vm.diskPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { saveVm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 380)
    }

    private func saveVm() {
        appState.editVm(
            id: vm.id,
            name: name,
            memoryMb: memoryGb * 1024,
            cpuCount: cpuCount,
            netEnabled: true
        )
        dismiss()
    }
}
