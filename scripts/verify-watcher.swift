import AppKit

/// Drives the real `ClipboardWatcher` against a private pasteboard with a unique name, so
/// it checks the capture rules without touching the clipboard in use, the running app or
/// its history — and so two runs at once cannot see each other's writes.
/// Compiled against the watcher's own sources by `verify-watcher.sh`.
///
/// It mimics each writer the way it actually writes. Chromium puts the text on first and
/// the type saying where it came from last; Bitwarden's desktop app writes the text and
/// then its concealed marker. The instant between those steps is one a timer cannot be
/// relied on to hit, so those cases call `poll()` directly and then let the run loop turn
/// for less than the watcher's settle before the second step — which is what makes them
/// fail if the wait is ever removed, not only if the read goes back to being immediate.
@main
struct VerifyWatcher {
    @MainActor
    static func main() {
        let board = NSPasteboard.withUniqueName()
        var captured: [(text: String, secret: Bool)] = []
        let watcher = ClipboardWatcher(pasteboard: board) { captured.append(($0, $1)) }
        watcher.start()

        let source = NSPasteboard.PasteboardType("org.chromium.source-url")
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let bitwarden = "chrome-extension://nngceckbapebfimnlniiiahkandclblb/popup/index.html"
        var failures = 0

        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.8)) }
        /// Shorter than the watcher's 50 ms settle, long enough for a read with no wait.
        func turn() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        func write(_ text: String, _ extras: [(NSPasteboard.PasteboardType, String)] = []) {
            board.clearContents()
            board.setString(text, forType: .string)
            for (type, value) in extras { board.setString(value, forType: type) }
        }
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "pass  \(what)" : "FAIL  \(what)")
            if !ok { failures += 1 }
        }
        /// Captured exactly once since `before`, with the expected secrecy.
        func capturedOnce(_ text: String, secret: Bool, since before: Int) -> Bool {
            let new = captured.dropFirst(before).filter { $0.text == text }
            return new.count == 1 && new[0].secret == secret
        }

        print("=== the rule on its own ===")
        check(PasswordManagerExtensions.ids.allSatisfy { id in
            id.count == 32 && id.allSatisfy { ("a"..."p").contains($0) }
        }, "every extension ID is 32 letters a–p")
        check(ClipboardWatcher.isFromPasswordManager(bitwarden), "Bitwarden's popup counts")
        check(ClipboardWatcher.isFromPasswordManager(
            "chrome-extension://nngceckbapebfimnlniiiahkandclblb/offscreen-document/index.html"),
            "Bitwarden's offscreen document counts")
        check(ClipboardWatcher.isFromPasswordManager("chrome-extension://jbkfoedolllekgbhcbcoahefnbanhhlh/"),
            "the Edge Add-ons build counts")
        check(ClipboardWatcher.isFromPasswordManager("CHROME-EXTENSION://NNGCECKBAPEBFIMNLNIIIAHKANDCLBLB\n"),
            "case, and a newline straight after the ID, do not matter")
        check(ClipboardWatcher.isFromPasswordManager(" chrome-extension://nngceckbapebfimnlniiiahkandclblb/x"),
            "a leading space does not matter")
        check(ClipboardWatcher.isFromPasswordManager(
            "chrome-extension://nngceckbapebfimnlniiiahkandclblb/popup/index.html#/view|{x}^%"),
            "stray characters later in the URL do not matter")
        check(!ClipboardWatcher.isFromPasswordManager(
            "chrome-extension://efaidnbmnnnibpcajpcglclefindmkaj/https://example.com/report.pdf"),
            "Adobe Acrobat's PDF viewer does not count")
        check(!ClipboardWatcher.isFromPasswordManager("https://vault.bitwarden.com/#/vault"),
            "a web page does not count, not even the password manager's own site")
        check(!ClipboardWatcher.isFromPasswordManager(
            "https://example.com/?next=chrome-extension://nngceckbapebfimnlniiiahkandclblb/"),
            "an ID mentioned further along a web page's URL does not count")
        check(!ClipboardWatcher.isFromPasswordManager("chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"),
            "an unknown extension does not count")
        check(!ClipboardWatcher.isFromPasswordManager("chrome-extension://nngceckbapebfimnlniiiahkandclbl/"),
            "an ID one letter short does not count")
        check(!ClipboardWatcher.isFromPasswordManager(""), "an empty source does not count")
        check(!ClipboardWatcher.isFromPasswordManager("not a url at all"), "garbage does not count")

        print("\n=== through the watcher ===")
        var before = captured.count
        write("plain text entry"); settle()
        check(capturedOnce("plain text entry", secret: false, since: before), "plain text is captured, shown")

        before = captured.count
        write("marked by an app")
        board.setData(Data(), forType: concealed)
        settle()
        check(capturedOnce("marked by an app", secret: true, since: before), "ConcealedType makes it secret")

        before = captured.count
        write("copied from bitwarden in brave", [(source, bitwarden)]); settle()
        check(capturedOnce("copied from bitwarden in brave", secret: true, since: before),
              "a copy from a password manager's extension is secret")

        before = captured.count
        write("copied from a web page", [(source, "https://example.com/some/page?q=1")]); settle()
        check(capturedOnce("copied from a web page", secret: false, since: before), "a copy from a web page is shown")

        before = captured.count
        write("text from a pdf in acrobat",
              [(source, "chrome-extension://efaidnbmnnnibpcajpcglclefindmkaj/https://example.com/a.pdf")])
        settle()
        check(capturedOnce("text from a pdf in acrobat", secret: false, since: before),
              "text from Acrobat's viewer is shown")

        before = captured.count
        write("\u{0}", [(source, bitwarden)]); settle()
        check(captured.count == before, "Bitwarden's NUL clear is not captured")

        before = captured.count
        write("   \n\t"); settle()
        check(captured.count == before, "whitespace alone is not captured")

        before = captured.count
        write("\u{200F}"); settle()
        check(capturedOnce("\u{200F}", secret: false, since: before),
              "a right-to-left mark on its own is kept: format characters are not nothing")

        before = captured.count
        write("transient")
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        settle()
        check(captured.count == before, "a transient copy is not captured")

        before = captured.count
        write("auto-generated")
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        settle()
        check(captured.count == before, "an auto-generated copy is not captured")

        before = captured.count
        write("our own write"); watcher.acknowledgeOwnWrite(); settle()
        check(captured.count == before, "our own write is not captured back")

        print("\n=== the instant between two steps of one write ===")
        before = captured.count
        board.clearContents()
        board.setString("password, text first", forType: .string)
        watcher.poll(); turn()                           // the unlucky moment
        board.setString(bitwarden, forType: source)      // Chromium's source arrives after the text
        settle()
        check(capturedOnce("password, text first", secret: true, since: before),
              "a source written after the text still makes it secret")

        before = captured.count
        board.clearContents()
        board.writeObjects(["bitwarden desktop password" as NSString])
        watcher.poll(); turn()
        board.setString("", forType: concealed)          // Bitwarden desktop marks after the text
        settle()
        check(capturedOnce("bitwarden desktop password", secret: true, since: before),
              "a concealed marker written after the text still makes it secret")

        before = captured.count
        board.clearContents()
        watcher.poll(); turn()                           // emptied, nothing written yet
        board.setString("written after the emptying", forType: .string)
        settle()
        check(capturedOnce("written after the emptying", secret: false, since: before),
              "a copy read just after the pasteboard was emptied is not lost")

        before = captured.count
        write("replaced at once")
        watcher.poll()
        write("the one that stayed")
        settle()
        check(capturedOnce("the one that stayed", secret: false, since: before)
              && !captured.dropFirst(before).contains { $0.text == "replaced at once" },
              "a change replaced before it settles is left to the next poll, and read once")

        before = captured.count
        write("copied a moment before ours")
        watcher.poll()
        write("our own write, inside the settle"); watcher.acknowledgeOwnWrite()
        settle()
        check(captured.count == before, "our own write inside the settle is not captured either")

        before = captured.count
        write("copied just before stopping")
        watcher.poll()
        watcher.stop()
        settle()
        check(captured.count == before, "nothing is captured once the watcher is stopped")

        board.releaseGlobally()
        print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
