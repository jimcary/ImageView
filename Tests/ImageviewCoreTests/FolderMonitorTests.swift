import Foundation
import Testing
@testable import ImageviewCore

private actor ChangeCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Test
func folderMonitorCoalescesBurstChanges() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewMonitor-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let counter = ChangeCounter()
    let monitor = FolderMonitor(debounceInterval: 0.15)
    try monitor.start(url: folder) {
        Task {
            await counter.increment()
        }
    }
    defer { monitor.stop() }

    for index in 0..<5 {
        try Data([UInt8(index)]).write(
            to: folder.appendingPathComponent("\(index).png")
        )
    }
    try await Task.sleep(for: .milliseconds(600))

    #expect(await counter.value == 1)
}

@Test
func corruptDecodeDoesNotPoisonFollowingValidDecode() throws {
    let corrupt = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewCorrupt-\(UUID().uuidString).png")
    try Data("not an image".utf8).write(to: corrupt)
    let valid = try TestImageFixtures.writePNG(width: 24, height: 16)
    defer {
        try? FileManager.default.removeItem(at: corrupt)
        try? FileManager.default.removeItem(at: valid)
    }
    let decoder = ImageDecoder()

    #expect(throws: ImageDecodeError.self) {
        try decoder.decode(url: corrupt)
    }
    #expect(try decoder.decode(url: valid).pixelSize == CGSize(width: 24, height: 16))
}
