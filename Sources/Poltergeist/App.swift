import SwiftUI
import AppKit
import PoltergeistKit

@main
struct PoltergeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // Freeze the language the app started with before Settings can change it.
        _ = AppLanguage.atLaunch
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 580)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("menu.clean")) {
                Button(L("action.rescan")) { model.rescanCurrent() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button(L("action.scanall")) { model.scanAll() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Strings

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}

func T(_ p: Phrase) -> String {
    switch p {
    case .raw(let s): return s
    case .key(let k, let a): return a.isEmpty ? L(k) : String(format: L(k), locale: Locale.current, arguments: a.map { $0 as CVarArg })
    }
}

func bytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, n), countStyle: .file)
}

func reason(_ r: String) -> String {
    r.hasPrefix("fail.") ? L(r) : r
}

// MARK: - Settings keys, language, access

enum Prefs {
    static let oldDownloadsDays = "oldDownloadsDays"
    static let oldProjectsDays = "oldProjectsDays"
    static let largeFileMB = "largeFileMB"
}

enum AppLanguage {
    static let key = "appLanguage"
    /// Language the app was started with ("" = follow the system).
    static let atLaunch: String = UserDefaults.standard.string(forKey: key) ?? ""

    static func apply(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

enum Access {
    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }
}

/// Moves a file to the Trash; apps in /Applications go through Finder so macOS can ask for the password.
enum SystemTrash {
    static func recycle(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            guard url.path.hasPrefix("/Applications/") else { throw error }
            let done = DispatchSemaphore(value: 0)
            var failure: Error?
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle([url]) { _, err in
                    failure = err
                    done.signal()
                }
            }
            done.wait()
            if let failure { throw failure }
        }
    }
}

// MARK: - Look

extension Tint {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .teal: return .teal
        case .indigo: return .indigo
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        case .purple: return .purple
        case .pink: return .pink
        case .yellow: return .yellow
        case .mint: return .mint
        case .brown: return .brown
        }
    }
}

extension View {
    /// The one accented action of a screen: tinted Liquid Glass on macOS 26, a filled button before.
    @ViewBuilder func prominentAction() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }
}
