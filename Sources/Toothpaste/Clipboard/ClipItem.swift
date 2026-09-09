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
    var preview: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
