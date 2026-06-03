import Darwin
import Foundation

struct RunningAppInfo: Identifiable, Equatable {
    nonisolated var id: String { bundleIdentifier }

    let kind: GroupedAppKind
    let bundleIdentifier: String
    let name: String
    let appURL: URL
    let executableURL: URL?
    let processIdentifier: pid_t?

    nonisolated init(bundleIdentifier: String, name: String, appURL: URL) {
        self.kind = .bundle
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.appURL = appURL
        self.executableURL = nil
        self.processIdentifier = nil
    }

    nonisolated init(executablePath: String, name: String, processIdentifier: pid_t? = nil) {
        let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
        self.kind = .executable
        self.bundleIdentifier = GroupedApp.executableIdentifier(for: executableURL.path)
        self.name = name
        self.appURL = executableURL
        self.executableURL = executableURL
        self.processIdentifier = processIdentifier
    }
}
