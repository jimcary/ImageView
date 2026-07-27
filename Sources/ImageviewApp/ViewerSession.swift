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
        let playbackKind: MediaPlaybackKind
        let subimageIndex: Int
        let subimageCount: Int
        let isSlideshowRunning: Bool
        let isLoading: Bool
        let errorMessage: String?
    }

    var onChange: ((Snapshot) -> Void)?
    var onFrame: ((CGImage) -> Void)?

    private var index = MediaIndex(items: [])
    private let preferences: PreferencesStore
    private let securityScopedAccess = SecurityScopedAccessSession()
    private var sourceImage: DecodedImage?
    private var displayedImage: CGImage?
    private var recipe = EditRecipe()
    private var generation = DecodeGeneration()
    private var decodeTask: Task<Void, Never>?
    private var framePlaybackTask: Task<Void, Never>?
    private var slideshowTask: Task<Void, Never>?
    private var prefetchTasks: [Task<Void, Never>] = []
    private var folderMonitor: FolderMonitor?
    private var cache: CostCache<MediaSubimageKey, DecodedImage>
    private var protectedCacheKey: MediaSubimageKey?
    private var sessionFolder: URL?
    private var sessionRecursive = false
    private var usesRecursivePreference = false
    private var sortOrder: MediaSortOrder = .name
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var playbackKind: MediaPlaybackKind = .still
    private var subimageIndex = 0
    private var subimageCount = 1
    private var isSlideshowRunning = false
    private var isLoading = false
    private var errorMessage: String?

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        cache = CostCache<MediaSubimageKey, DecodedImage>(
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
            playbackKind: playbackKind,
            subimageIndex: subimageIndex,
            subimageCount: subimageCount,
            isSlideshowRunning: isSlideshowRunning,
            isLoading: isLoading,
            errorMessage: errorMessage
        )
    }

    func open(urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        securityScopedAccess.release()
        do {
            let values = try urls[0].resourceValues(forKeys: [.isDirectoryKey])
            if urls.count == 1, values.isDirectory == true {
                try open(folder: urls[0])
                return
            }

            let supportedURLs = urls.filter(MediaTypeRegistry.isSupported(url:))
            if supportedURLs.count == 1, let fileURL = supportedURLs.first {
                let folder = securityScopedAccess.activate(
                    folderURL: fileURL.deletingLastPathComponent()
                )
                let scanned = try FolderScanner().scan(
                    folder: folder,
                    recursive: false
                )
                let sorted = MediaItemSorter.sorted(scanned, by: sortOrder)
                index.replaceItems(sorted)
                if let selected = sorted.first(where: {
                    $0.url.standardizedFileURL == fileURL.standardizedFileURL
                }) {
                    index.select(id: selected.id)
                }
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
            securityScopedAccess.release()
            publishError(error.localizedDescription)
        }
    }

    func open(folder: URL) throws {
        let folder = securityScopedAccess.activate(folderURL: folder)
        sessionFolder = folder
        sessionRecursive = preferences.recursiveScan
        usesRecursivePreference = true
        let items: [MediaItem]
        do {
            items = try FolderScanner().scan(folder: folder, recursive: sessionRecursive)
        } catch {
            securityScopedAccess.release()
            throw error
        }
        index.replaceItems(MediaItemSorter.sorted(items, by: sortOrder))
        startMonitoring(folder: folder)
        decodeCurrent()
    }

    func move(_ direction: NavigationDirection) {
        stopFramePlayback()
        guard index.move(direction, wraps: preferences.wrapsNavigation) != nil else {
            return
        }
        decodeCurrent()
    }

    func select(id: MediaItem.ID) {
        stopFramePlayback()
        index.select(id: id)
        decodeCurrent()
    }

    func moveSubimage(_ delta: Int) {
        guard playbackKind == .document, subimageCount > 1 else {
            return
        }
        let target = min(max(subimageIndex + delta, 0), subimageCount - 1)
        guard target != subimageIndex else {
            return
        }
        decodeSubimage(at: target)
    }

    func toggleSlideshow(interval: TimeInterval? = nil) {
        if isSlideshowRunning {
            stopSlideshow()
            publish()
            return
        }
        isSlideshowRunning = true
        let delay = max(interval ?? preferences.slideshowInterval, 1)
        slideshowTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(delay * 1_000_000_000)
                    )
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else {
                    return
                }
                self.advanceSlideshow()
            }
        }
        publish()
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

    func moveCurrentToTrash() throws {
        guard let current = index.current else {
            throw ImageDecodeError.cannotOpen
        }
        _ = try FileManager.default.trashItem(
            at: current.url,
            resultingItemURL: nil
        )
        _ = index.removeCurrent()
        decodeCurrent()
    }

    func setFinderLabel(_ labelNumber: Int) throws {
        guard (0...7).contains(labelNumber),
              let current = index.current else {
            throw ImageDecodeError.cannotOpen
        }
        var url = current.url
        var values = URLResourceValues()
        values.labelNumber = labelNumber
        try url.setResourceValues(values)

        let refreshed = MediaItem(
            url: url,
            resourceIdentifier: current.resourceIdentifier,
            fileSize: current.fileSize,
            createdAt: current.createdAt,
            modifiedAt: current.modifiedAt,
            finderLabel: labelNumber,
            finderOrder: current.finderOrder
        )
        let replacement = index.items.map {
            $0.id == current.id ? refreshed : $0
        }
        index.replaceItems(
            MediaItemSorter.sorted(replacement, by: sortOrder),
            preserving: current.id
        )
        publish()
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
        guard index.current != nil else {
            throw ImageDecodeError.cannotOpen
        }
        let rendered = try renderedCurrentImage()
        try ExportCoordinator().saveAs(
            image: rendered,
            sourceProperties: ExportMetadata.adjustedProperties(
                sourceImage?.properties ?? [:],
                renderedImage: rendered
            ),
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
        let rendered = try renderedCurrentImage()
        try ExportCoordinator().overwrite(
            image: rendered,
            sourceProperties: ExportMetadata.adjustedProperties(
                sourceImage?.properties ?? [:],
                renderedImage: rendered
            ),
            originalURL: sourceURL,
            format: format,
            metadataPolicy: metadataPolicy
        )
        open(urls: [sourceURL])
    }

    func cancel() {
        decodeTask?.cancel()
        stopFramePlayback()
        stopSlideshow()
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        folderMonitor?.stop()
        folderMonitor = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        securityScopedAccess.release()
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
        stopFramePlayback()
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()

        guard let current = index.current else {
            sourceImage = nil
            displayedImage = nil
            playbackKind = .still
            subimageIndex = 0
            subimageCount = 1
            errorMessage = nil
            isLoading = false
            publish()
            return
        }

        recipe = EditRecipe()
        playbackKind = .still
        subimageIndex = 0
        subimageCount = 1
        errorMessage = nil
        isLoading = true
        let currentGeneration = generation.begin()
        let cacheKey = MediaSubimageKey(mediaID: current.id, index: 0)

        if let cached = cache.value(for: cacheKey) {
            accept(cached, for: cacheKey, generation: currentGeneration)
            prefetch(around: index.currentIndex)
            return
        }

        let url = current.url
        decodeTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ImageDecoder().decode(url: url, page: 0) }
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
        for cacheKey: MediaSubimageKey,
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
        do {
            displayedImage = try ImageRenderer().render(decoded.image, recipe: recipe)
        } catch {
            displayedImage = nil
            playbackKind = .still
            subimageIndex = 0
            subimageCount = 1
            isLoading = false
            errorMessage = error.localizedDescription
            publish()
            return
        }
        playbackKind = decoded.playbackKind
        subimageIndex = decoded.index
        subimageCount = decoded.frameCount
        isLoading = false
        errorMessage = nil
        publish()
        if decoded.playbackKind == .animation {
            scheduleNextAnimationFrame(after: decoded, generation: currentGeneration)
        }
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
                let key = MediaSubimageKey(mediaID: item.id, index: 0)
                return mutableCache.value(for: key) == nil
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
                let key = MediaSubimageKey(mediaID: item.id, index: 0)
                self.cache.insert(decoded, for: key, cost: cost)
            }
            prefetchTasks.append(task)
        }
    }

    private func decodeSubimage(at targetIndex: Int) {
        guard let current = index.current else {
            return
        }
        stopFramePlayback()
        decodeTask?.cancel()
        errorMessage = nil
        isLoading = true
        let currentGeneration = generation.begin()
        let cacheKey = MediaSubimageKey(mediaID: current.id, index: targetIndex)
        if let cached = cache.value(for: cacheKey) {
            accept(cached, for: cacheKey, generation: currentGeneration)
            return
        }

        let url = current.url
        decodeTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ImageDecoder().decode(url: url, page: targetIndex) }
            }.value
            guard let self, !Task.isCancelled,
                  self.generation.isCurrent(currentGeneration) else {
                return
            }
            switch result {
            case let .success(decoded):
                self.accept(decoded, for: cacheKey, generation: currentGeneration)
            case let .failure(error):
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.publish()
            }
        }
        publish()
    }

    private func scheduleNextAnimationFrame(
        after currentFrame: DecodedImage,
        generation currentGeneration: UInt64
    ) {
        guard let current = index.current, currentFrame.frameCount > 1 else {
            return
        }
        let mediaID = current.id
        let url = current.url
        let nextIndex = FramePlaybackPolicy.nextFrame(
            after: currentFrame.index,
            frameCount: currentFrame.frameCount
        )
        let delay = FramePlaybackPolicy.safeDelay(currentFrame.duration)
        framePlaybackTask = Task { [weak self] in
            async let decodedResult = Task.detached(priority: .utility) {
                Result { try ImageDecoder().decode(url: url, page: nextIndex) }
            }.value
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(delay * 1_000_000_000)
                )
            } catch {
                return
            }
            let result = await decodedResult
            guard let self, !Task.isCancelled,
                  self.generation.isCurrent(currentGeneration),
                  self.index.current?.id == mediaID,
                  case let .success(decoded) = result else {
                return
            }
            let key = MediaSubimageKey(mediaID: mediaID, index: decoded.index)
            if let protectedCacheKey = self.protectedCacheKey {
                self.cache.protect(protectedCacheKey, false)
            }
            let cost = decoded.image.bytesPerRow * decoded.image.height
            self.cache.insert(decoded, for: key, cost: cost, protected: true)
            self.protectedCacheKey = key
            self.sourceImage = decoded
            self.subimageIndex = decoded.index
            do {
                let rendered = try ImageRenderer().render(decoded.image, recipe: self.recipe)
                self.displayedImage = rendered
                self.onFrame?(rendered)
            } catch {
                self.errorMessage = error.localizedDescription
                self.publish()
                return
            }
            self.scheduleNextAnimationFrame(
                after: decoded,
                generation: currentGeneration
            )
        }
    }

    private func advanceSlideshow() {
        if playbackKind == .document, subimageIndex + 1 < subimageCount {
            moveSubimage(1)
            return
        }
        if index.currentIndex == index.items.indices.last,
           !preferences.wrapsNavigation {
            stopSlideshow()
            publish()
            return
        }
        move(.next)
    }

    private func stopFramePlayback() {
        framePlaybackTask?.cancel()
        framePlaybackTask = nil
    }

    private func stopSlideshow() {
        slideshowTask?.cancel()
        slideshowTask = nil
        isSlideshowRunning = false
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
