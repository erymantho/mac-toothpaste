import Foundation

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var pinned: Bool

    /// Marked secret by the source app (password managers set
    /// `org.nspasteboard.ConcealedType`). Never written to disk.
    var concealed: Bool

    init(text: String, concealed: Bool = false) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.pinned = false
        self.concealed = concealed
    }

    /// The `(19)` shown next to each row — character count, as in 0xpaste.
    var characterCount: Int { text.count }

    /// Single-line form for list rows; the stored text keeps its newlines.
    ///
    /// Every kind of line break becomes a space. A Windows line ending is one `Character`,
    /// `"\r\n"`, and replacing `"\n"` alone left its `\r`, where the one-line row then
    /// stopped: a two-line snippet showed only its first line.
    var preview: String {
        String(text.map { $0.isNewline || $0 == "\t" ? " " : $0 })
            .trimmingCharacters(in: .whitespaces)
    }
}
