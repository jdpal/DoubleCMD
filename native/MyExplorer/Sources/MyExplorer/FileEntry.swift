import Foundation
import UniformTypeIdentifiers

struct FileEntry: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let byteCount: Int64?
    let modifiedAt: Date?
    let typeDescription: String

    static func parentEntry(for directory: URL) -> FileEntry? {
        let parent = directory.deletingLastPathComponent()
        guard parent.path != directory.path else { return nil }

        return FileEntry(
            url: parent,
            name: "..",
            isDirectory: true,
            byteCount: nil,
            modifiedAt: nil,
            typeDescription: "Parent Folder"
        )
    }

    init(url: URL, name: String? = nil, isDirectory: Bool? = nil, byteCount: Int64? = nil, modifiedAt: Date? = nil, typeDescription: String? = nil) {
        self.url = url
        self.id = url
        self.name = name ?? url.lastPathComponent

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey])
        self.isDirectory = isDirectory ?? values?.isDirectory ?? false
        self.byteCount = byteCount ?? values?.fileSize.map(Int64.init)
        self.modifiedAt = modifiedAt ?? values?.contentModificationDate

        if let typeDescription {
            self.typeDescription = typeDescription
        } else if self.isDirectory {
            self.typeDescription = "Folder"
        } else if let description = values?.contentType?.localizedDescription {
            self.typeDescription = description
        } else {
            self.typeDescription = "File"
        }
    }
}
