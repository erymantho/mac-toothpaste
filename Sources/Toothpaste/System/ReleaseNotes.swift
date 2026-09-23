import Foundation

/// A tag annotation, read as release notes.
///
/// Annotations are where this project writes what a version changed, and they are shown
/// twice: before an update, so someone can decide whether to take it, and after, as what
/// they actually got. The people using the tool asked for one distinction in both places —
/// what is new, apart from what was broken and no longer is — so an annotation can carry
/// labelled sections:
///
///     One or two sentences for everyone, if there is something everyone must know.
///
///     New:
///     - Drag an entry to a field to click and type there. Off by default.
///
///     Fixed:
///     - Clicking a row while another window was in front took two clicks.
///
/// **The labels are words with a colon, never Markdown headings.** `git tag` cleans a
/// message by deleting every line that starts with `#`, so a `### New` heading vanishes
/// between writing the tag and reading it back. Measured, not assumed.
///
/// An annotation without labels — every tag up to and including 1.2.1 — reads as one block
/// of prose, exactly as it did before sections existed.
///
/// Text after the last section belongs to that section. Closing remarks therefore go in
/// the summary, at the top, where everyone reads them first anyway.
struct ReleaseNotes: Equatable {
    enum Kind: Equatable {
        case new, changed, fixed, removed
        /// A heading this parser has no meaning for — "Known issues:", "Upgrading:". Shown
        /// under its own words. Folded into the section above, as it first was, a known
        /// issue after a list of fixes read as one more fix.
        case other(String)
    }

    struct Section: Equatable {
        let kind: Kind
        var items: [String]
    }

    /// Prose before the first label, reflowed. For an unlabelled annotation, all of it.
    private(set) var summary = ""

    /// In the order they were written. A label used twice is merged into its first
    /// occurrence, so no heading ever appears twice; a label with nothing under it is
    /// dropped.
    private(set) var sections: [Section] = []

    var isEmpty: Bool { summary.isEmpty && sections.isEmpty }

    init(_ annotation: String) {
        var lines = annotation
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        // A signed tag carries its signature in the same message, after the text, and
        // `%(contents)` returns both. It is not release notes, and left in it would be glued
        // onto the last bullet as a block of base64 — a fork that signs its tags would show
        // it as a bug fix. Reproduced with an SSH-signed tag; no tag here is signed yet.
        if let signature = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN ") }) {
            lines.removeSubrange(signature...)
        }

        var prose: [String] = []
        var found: [Section] = []
        var current: Int?
        var item: String?

        func finishItem() {
            if let text = item, let index = current { found[index].items.append(text) }
            item = nil
        }

        for line in lines {
            // An unknown heading only counts once sections have begun. Before the first
            // label a line ending in a colon is ordinary prose, which is where anything
            // addressed to everyone belongs.
            if let kind = Self.label(line) ?? (current == nil ? nil : Self.heading(line)) {
                finishItem()
                if let existing = found.firstIndex(where: { $0.kind == kind }) {
                    current = existing
                } else {
                    found.append(Section(kind: kind, items: []))
                    current = found.count - 1
                }
                continue
            }

            // Everything before the first label is the summary, kept as written so the
            // reflow below can respect its paragraphs.
            guard current != nil else {
                prose.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                finishItem()
            } else if let text = Self.bulletText(trimmed) {
                finishItem()
                item = text
            } else if let text = item {
                // A wrapped bullet, continued on the next line.
                item = text + " " + trimmed
            } else {
                // Prose inside a section: each paragraph becomes one item.
                item = trimmed
            }
        }
        finishItem()

        summary = Self.reflowed(prose.joined(separator: "\n"))
        sections = found.filter { !$0.items.isEmpty }
    }

    /// Whole-line labels only, flush left, so prose that merely begins with "Fixed:" — or
    /// an indented continuation line — can never open a section. The canonical spellings
    /// are New, Changed, Fixed and Removed; the others are accepted so that whoever writes
    /// the next tag does not have to look this up.
    private static let labels: [String: Kind] = [
        "new": .new, "new features": .new, "new feature": .new, "features": .new,
        "feature": .new, "added": .new,
        "changed": .changed, "changes": .changed, "change": .changed,
        "improvements": .changed, "improved": .changed,
        "fixed": .fixed, "fixes": .fixed, "fix": .fixed, "bug fixes": .fixed,
        "bug fix": .fixed, "bugfixes": .fixed, "bugfix": .fixed,
        "removed": .removed, "removals": .removed,
    ]

    private static func label(_ line: String) -> Kind? {
        guard let first = line.first, !first.isWhitespace else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(":") else { return nil }
        let name = trimmed.dropLast().trimmingCharacters(in: .whitespaces).lowercased()
        return labels[name]
    }

    /// Any other flush-left line of one to four words ending in a colon, starting with a
    /// capital and free of sentence punctuation. The capital is what keeps a wrapped bullet
    /// whose continuation happens to read "the following:" from becoming a heading.
    private static func heading(_ line: String) -> Kind? {
        guard let first = line.first, first.isUppercase else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(":"), bulletText(trimmed) == nil else { return nil }
        let name = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
        let words = name.split(separator: " ")
        guard (1...4).contains(words.count),
              !name.contains(where: { ".,;:!?()[]{}`\"/\\".contains($0) })
        else { return nil }
        return .other(name)
    }

    /// `- `, `* `, `• ` and `+ `, and numbered items such as `1. ` or `2) `. A numbered list
    /// keeps its order as bullets; the numbers themselves are dropped.
    private static let bulletMarkers = ["- ", "* ", "\u{2022} ", "+ "]

    private static func bulletText(_ trimmed: String) -> String? {
        for marker in bulletMarkers where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        if let number = trimmed.range(of: #"^[0-9]{1,3}[.)] "#, options: .regularExpression) {
            return String(trimmed[number.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Joins the lines within a paragraph so a view can wrap the text to whatever width
    /// it has.
    ///
    /// Annotations are hard-wrapped for a terminal, and re-wrapping an already-wrapped
    /// paragraph to a narrower width leaves a trail of orphans — every line that no longer
    /// fits sheds two or three words onto a line of its own. It reads as broken alignment
    /// rather than as wrapping, which is how it was reported.
    ///
    /// Blank lines keep separating paragraphs, and a line that is indented or starts a
    /// bullet is left where it is: there the break was meant.
    private static func reflowed(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                var lines: [String] = []
                for raw in paragraph.components(separatedBy: "\n") {
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }

                    let deliberate = raw.hasPrefix(" ") || raw.hasPrefix("\t")
                        || bulletText(trimmed) != nil

                    if deliberate || lines.isEmpty {
                        lines.append(deliberate ? raw : trimmed)
                    } else {
                        lines[lines.count - 1] += " " + trimmed
                    }
                }
                return lines.joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
