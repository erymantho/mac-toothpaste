import SwiftUI

/// Release notes laid out the way the people reading them asked for: what is new, apart
/// from what was fixed. Shown before an update in the Updates tab and after one in
/// `WhatsNewView`, so both read the same way. See `ReleaseNotes` for how an annotation is
/// split.
struct ReleaseNotesView: View {
    let notes: ReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !notes.summary.isEmpty {
                Text(Self.rich(notes.summary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(notes.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    Label(Self.title(section.kind), systemImage: Self.symbol(section.kind))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Self.tint(section.kind))

                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\u{2022}").foregroundStyle(.secondary)
                            Text(Self.rich(item)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func title(_ kind: ReleaseNotes.Kind) -> String {
        switch kind {
        case .new: return "New features"
        case .changed: return "Changed"
        case .fixed: return "Bug fixes"
        case .removed: return "Removed"
        case let .other(heading): return heading
        }
    }

    private static func symbol(_ kind: ReleaseNotes.Kind) -> String {
        switch kind {
        case .new: return "sparkles"
        case .changed: return "arrow.triangle.2.circlepath"
        case .fixed: return "wrench.and.screwdriver"
        case .removed: return "minus.circle"
        case .other: return "text.bubble"
        }
    }

    /// Only the two kinds people asked to tell apart get a colour of their own, and both
    /// come from `Theme`, which states a light and a dark value for each. Not the accent
    /// colour: see `Theme.newFeature` for what that did under a yellow or green accent.
    private static func tint(_ kind: ReleaseNotes.Kind) -> Color {
        switch kind {
        case .new: return Theme.newFeature
        case .fixed: return Theme.ok
        case .changed, .removed, .other: return .secondary
        }
    }

    /// Plain text, except that a span in backticks is set in the monospaced font — the one
    /// piece of markup this project's own annotations have used (`git pull && make install`).
    ///
    /// Deliberately not a Markdown parser. One was tried and measured: it ate the
    /// backslashes out of `\\fileserver\share\*.txt`, decoded `&amp;`, struck through text
    /// between tildes, bolded `__init__`, and turned any URL or address in an annotation —
    /// which comes from whatever remote a clone points at — into a live link. In a tool
    /// whose users paste Windows paths all day, a release note naming one has to survive
    /// as written.
    private static func rich(_ text: String) -> AttributedString {
        let parts = text.components(separatedBy: "`")
        // An unmatched backtick is just a character.
        guard parts.count > 1, parts.count % 2 == 1 else { return AttributedString(text) }
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            var piece = AttributedString(part)
            if index % 2 == 1 { piece.font = .system(.callout, design: .monospaced) }
            result += piece
        }
        return result
    }
}

/// Every version since the one someone was on, newest first, so that skipping a release
/// does not mean never hearing what it added. Only the newest used to be shown: someone on
/// 1.2.1 offered a fixes-only 1.3.1 would have missed that 1.3.0 introduced a feature.
///
/// One version shows exactly as `ReleaseNotesView` does; several get their version number
/// above each block.
struct ReleaseNotesList: View {
    let releases: [Updater.Release]

    /// The version the heading above this list already names. A lone release matching it
    /// needs no label of its own; any other lone release does, or its notes would read as
    /// that version's — which is what happened when the newest tag in a range was empty
    /// and the one before it filled the space unlabelled.
    var named: String? = nil

    /// Versions whose tag says nothing are left out rather than shown as a bare number.
    static func readable(_ releases: [Updater.Release]) -> [(version: String, notes: ReleaseNotes)] {
        releases
            .map { (version: $0.version, notes: ReleaseNotes($0.annotation)) }
            .filter { !$0.notes.isEmpty }
    }

    private var entries: [(version: String, notes: ReleaseNotes)] { Self.readable(releases) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 8) {
                    if entries.count > 1 || entries.first?.version != named {
                        Text(entry.version)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ReleaseNotesView(notes: entry.notes)
                }
            }
        }
    }
}
