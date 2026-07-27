import Foundation
import Testing
@testable import ImageviewCore

@Test
func scannerIncludesImagesAndSkipsUnsupportedFiles() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    try Data().write(to: folder.appendingPathComponent("b.png"))
    try Data().write(to: folder.appendingPathComponent("a.JPG"))
    try Data().write(to: folder.appendingPathComponent("note.txt"))

    let result = try FolderScanner().scan(folder: folder, recursive: false)

    #expect(result.map(\.url.lastPathComponent).sorted() == ["a.JPG", "b.png"])
}

@Test
func scannerDoesNotDescendWhenRecursiveIsFalse() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let nested = folder.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data().write(to: nested.appendingPathComponent("inside.png"))

    let result = try FolderScanner().scan(folder: folder, recursive: false)

    #expect(result.isEmpty)
}

private func makeTemporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
