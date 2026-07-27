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

@Test
func explicitURLScanLoadsFinderMetadataAndPreservesInputOrder() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let second = folder.appendingPathComponent("second.png")
    let first = folder.appendingPathComponent("first.png")
    try Data().write(to: first)
    try Data().write(to: second)
    var labeledURL = second
    var values = URLResourceValues()
    values.labelNumber = 3
    try labeledURL.setResourceValues(values)

    let result = FolderScanner().scan(urls: [second, first])

    #expect(result.map(\.url.lastPathComponent) == ["second.png", "first.png"])
    #expect(result.map(\.finderOrder) == [0, 1])
    #expect(result[0].finderLabel == 3)
    #expect(result.allSatisfy { !$0.resourceIdentifier.isEmpty })
}

private func makeTemporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
