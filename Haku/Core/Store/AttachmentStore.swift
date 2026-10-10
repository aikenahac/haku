import AppKit
import Foundation
import UniformTypeIdentifiers

/// Attachments are context only: copied to a temp folder, passed through as paths, deleted after use.
@MainActor
final class AttachmentStore {
    private var owners: [UUID: Set<UUID>] = [:]   // attachment → jobs still using it

    func importFile(_ url: URL) throws -> Attachment {
        let id = UUID()
        let dir = AppPaths.attachments.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: url, to: dest)
        return Attachment(id: id, fileName: url.lastPathComponent, url: dest, isImage: Self.isImage(dest))
    }

    func importImage(_ image: NSImage, name: String = "pasted.png") throws -> Attachment {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try importData(png, name: name)
    }

    func importData(_ data: Data, name: String) throws -> Attachment {
        let id = UUID()
        let dir = AppPaths.attachments.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        try data.write(to: dest)
        return Attachment(id: id, fileName: name, url: dest, isImage: Self.isImage(dest))
    }

    /// A job keeps its attachments alive until it finishes.
    func retain(_ attachments: [Attachment], for job: UUID) {
        for a in attachments { owners[a.id, default: []].insert(job) }
    }

    func release(job: UUID) {
        for (id, jobs) in owners where jobs.contains(job) {
            var j = jobs; j.remove(job)
            owners[id] = j.isEmpty ? nil : j
            if j.isEmpty { deleteFolder(id) }
        }
    }

    /// Deletes attachments no job is holding.
    func discard(_ attachments: [Attachment]) {
        for a in attachments where owners[a.id] == nil { deleteFolder(a.id) }
    }

    func purgeAll() {
        try? FileManager.default.removeItem(at: AppPaths.attachments)
        owners = [:]
    }

    private func deleteFolder(_ id: UUID) {
        try? FileManager.default.removeItem(at: AppPaths.attachments.appendingPathComponent(id.uuidString))
    }

    static func isImage(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image)) ?? false
    }
}
