import AppKit
import ImageviewCore

@MainActor
final class ViewerSession {
    struct Snapshot {
        let items: [MediaItem]
        let current: MediaItem?
        let position: Int?
        let image: CGImage?
        let sourceProperties: [CFString: Any]?
        let recipe: EditRecipe
        let isLoading: Bool
        let errorMessage: String?
    }

    var onChange: ((Snapshot) -> Void)?

    private var index = MediaIndex(items: [])
    private let preferences: PreferencesStore
    private var sourceImage: DecodedImage?
    private var displayedImage: CGImage?
    private var recipe = EditRecipe()
    private var generation = DecodeGeneration()
    private var decodeTask: Task<Void, Never>?
    private var prefetchTasks: [Task<Void, Never>] = []
    private var folderMonitor: FolderMonitor?
    private var cache: CostCache<String, DecodedImage>
    private var protectedCacheKey: String?
    private var sessionFolder: URL?
    private var sessionRecursive = false
    private var usesRecursivePreference = false
    private var sortOrder: MediaSortOrder = .name
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var isLoading = false
    private var errorMessage: String?

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        cache = CostCache<String, DecodedImage>(
            costLimit: preferences.cacheLimitMB * 1_024 * 1_024
        )
        let pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        pressureSource.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure()
            }
        }
        pressureSource.resume()
        memoryPressureSource = pressureSource
    }

    var snapshot: Snapshot {
        Snapshot(
            items: index.items,
            current: index.current,
            position: index.currentIndex.map { $0 + 1 },
            image: displayedImage,
            sourceProperties: sourceImage?.properties,
            recipe: recipe,
            isLoading: isLoading,
            errorMessage: errorMessage
        )
    }

    func open(urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        do {
            let values = try urls[0].resourceValues(forKeys: [.isDirectoryKey])
            if urls.count == 1, values.isDirectory == true {
                try open(folder: urls[0])
                return
            }

            let supportedURLs = urls.filter(MediaTypeRegistry.isSupported(url:))
            if supportedURLs.count == 1, let fileURL = supportedURLs.first {
                let scanned = try FolderScanner().scan(
                    folder: fileURL.deletingLastPathComponent(),
                    recursive: false
                )
                let sorted = MediaItemSorter.sorted(scanned, by: sortOrder)
                index.replaceItems(sorted)
                if let selected = sorted.first(where: {
                    $0.url.standardizedFileURL == fileURL.standardizedFileURL
                }) {
                    index.select(id: selected.id)
                }
                let folder = fileURL.deletingLastPathComponent()
                sessionFolder = folder
                sessionRecursive = false
                usesRecursivePreference = false
                startMonitoring(folder: folder)
            } else {
                let items = supportedURLs.enumerated().map { order, url in
                    MediaItem(url: url, finderOrder: order)
                }
                index.replaceItems(MediaItemSorter.sorted(items, by: sortOrder))
                sessionFolder = nil
                sessionRecursive = false
                usesRecursivePreference = false
                folderMonitor?.stop()
                folderMonitor = nil
            }
            decodeCurrent()
        } catch {
            publishError(error.localizedDescription)
        }
    }

    func open(folder: URL) throws {
        sessionFolder = folder
        sessionRecursive = preferences.recursiveScan
        usesRecursivePreference = true
        let items = try FolderScanner().scan(folder: folder, recursive: sessionRecursive)
        index.replaceItems(MediaItemSorter.sorted(items, by: sortOrder))
        startMonitoring(folder: folder)
        decodeCurrent()
    }

    func move(_ direction: NavigationDirection) {
        guard index.move(direction, wraps: preferences.wrapsNavigation) != nil else {
            return
        }
        decodeCurrent()
    }

    func select(id: MediaItem.ID) {
        index.select(id: id)
        decodeCurrent()
    }

    func refreshCurrentFolder() {
        guard let folder = sessionFolder else {
            return
        }
        do {
            let replacement = try FolderScanner().scan(
                folder: folder,
                recursive: sessionRecursive
            )
            index.replaceItems(MediaItemSorter.sorted(replacement, by: sortOrder))
            decodeCurrent()
        } catch {
            publishError(error.localizedDescription)
        }
    }

    func rotate(clockwise: Bool) {
        recipe = EditRecipe(
            rotationQuarterTurns: recipe.rotationQuarterTurns + (clockwise ? 1 : -1),
            flipHorizontal: recipe.flipHorizontal,
            flipVertical: recipe.flipVertical,
            crop: recipe.crop
        )
        renderRecipe()
    }

    func flip(horizontal: Bool) {
        recipe = EditRecipe(
            rotationQuarterTurns: recipe.rotationQuarterTurns,
            flipHorizontal: horizontal ? !recipe.flipHorizontal : recipe.flipHorizontal,
            flipVertical: horizontal ? recipe.flipVertical : !recipe.flipVertical,
            crop: recipe.crop
        )
        renderRecipe()
    }

    func setCrop(_ crop: NormalizedRect) {
        recipe = EditRecipe(
            rotationQuarterTurns: recipe.rotationQuarterTurns,
            flipHorizontal: recipe.flipHorizontal,
            flipVertical: recipe.flipVertical,
            crop: crop
        )
        publish()
    }

    func renderedCurrentImage() throws -> CGImage {
        guard let sourceImage else {
            throw ImageDecodeError.cannotDecode
        }
        return try ImageRenderer().render(sourceImage.image, recipe: recipe)
    }

    func saveCurrent(
        to destinationURL: URL,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        guard let sourceURL = index.current?.url else {
            throw ImageDecodeError.cannotOpen
        }
        try CropSaveWorkflow().save(
            sourceURL: sourceURL,
            recipe: recipe,
            destinationURL: destinationURL,
            format: format,
            metadataPolicy: metadataPolicy
        )
        open(urls: [destinationURL])
    }

    func overwriteCurrent(
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        guard let sourceURL = index.current?.url else {
            throw ImageDecodeError.cannotOpen
        }
        try CropSaveWorkflow().overwrite(
            sourceURL: sourceURL,
            recipe: recipe,
            format: format,
            metadataPolicy: metadataPolicy
        )
        open(urls: [sourceURL])
    }

    func cancel() {
        decodeTask?.cancel()
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        folderMonitor?.stop()
        folderMonitor = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        generation.invalidate()
    }

    func setSortOrder(_ order: MediaSortOrder) {
        sortOrder = order
        index.replaceItems(MediaItemSorter.sorted(index.items, by: order))
        publish()
    }

    func applyPreferences() {
        cache.setCostLimit(preferences.cacheLimitMB * 1_024 * 1_024)
        guard usesRecursivePreference,
              sessionRecursive != preferences.recursiveScan else {
            return
        }
        sessionRecursive = preferences.recursiveScan
        refreshCurrentFolder()
    }

    func handleMemoryPressure() {
        cache.removeUnprotected()
    }

    private func decodeCurrent() {
        decodeTask?.cancel()
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()

        guard let current = index.current else {
            sourceImage = nil
            displayedImage = nil
            errorMessage = nil
            isLoading = false
            publish()
            return
        }

        recipe = EditRecipe()
        errorMessage = nil
        isLoading = true
        let currentGeneration = generation.begin()
        let cacheKey = current.id

        if let cached = cache.value(for: cacheKey) {
            accept(cached, for: cacheKey, generation: currentGeneration)
            prefetch(around: index.currentIndex)
            return
        }

        let url = current.url
        decodeTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ImageDecoder().decode(url: url) }
            }.value
            guard let self, !Task.isCancelled,
                  self.generation.isCurrent(currentGeneration) else {
                return
            }
            switch result {
            case let .success(decoded):
                self.accept(decoded, for: cacheKey, generation: currentGeneration)
                self.prefetch(around: self.index.currentIndex)
            case let .failure(error):
                self.sourceImage = nil
                self.displayedImage = nil
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.publish()
            }
        }
        publish()
    }

    private func accept(
        _ decoded: DecodedImage,
        for cacheKey: String,
        generation currentGeneration: UInt64
    ) {
        guard generation.isCurrent(currentGeneration) else {
            return
        }
        if let protectedCacheKey {
            cache.protect(protectedCacheKey, false)
        }
        let cost = decoded.image.bytesPerRow * decoded.image.height
        cache.insert(decoded, for: cacheKey, cost: cost, protected: true)
        protectedCacheKey = cacheKey
        sourceImage = decoded
        displayedImage = decoded.image
        isLoading = false
        errorMessage = nil
        publish()
    }

    private func renderRecipe() {
        guard let sourceImage else {
            return
        }
        do {
            displayedImage = try ImageRenderer().render(sourceImage.image, recipe: recipe)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        publish()
    }

    private func prefetch(around currentIndex: Int?) {
        guard let currentIndex else {
            return
        }
        let candidates = [-2, -1, 1, 2]
            .map { currentIndex + $0 }
            .filter(index.items.indices.contains)
            .map { index.items[$0] }
            .filter { item in
                var mutableCache = cache
                return mutableCache.value(for: item.id) == nil
            }

        for item in candidates {
            let task = Task { [weak self] in
                let result = await Task.detached(priority: .utility) {
                    Result { try ImageDecoder().decode(url: item.url) }
                }.value
                guard let self, !Task.isCancelled,
                      case let .success(decoded) = result else {
                    return
                }
                let cost = decoded.image.bytesPerRow * decoded.image.height
                self.cache.insert(decoded, for: item.id, cost: cost)
            }
            prefetchTasks.append(task)
        }
    }

    private func publishError(_ message: String) {
        errorMessage = message
        isLoading = false
        publish()
    }

    private func publish() {
        onChange?(snapshot)
    }

    private func startMonitoring(folder: URL) {
        folderMonitor?.stop()
        let monitor = FolderMonitor()
        do {
            try monitor.start(url: folder) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshCurrentFolder()
                }
            }
            folderMonitor = monitor
        } catch {
            folderMonitor = nil
        }
    }
}
