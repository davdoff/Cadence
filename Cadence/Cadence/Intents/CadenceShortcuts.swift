import AppIntents

/// Registers Cadence's Siri / App Shortcuts phrases so `AskCadenceIntent`
/// is discoverable without the user manually adding a shortcut.
///
/// Phase 0 spike (CADENCE_README §12): a single phrase to prove the
/// end-to-end voice path. More phrasings land in Phase 1.
struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskCadenceIntent(),
            phrases: [
                "Ask \(.applicationName)"
            ],
            shortTitle: "Ask Cadence",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
