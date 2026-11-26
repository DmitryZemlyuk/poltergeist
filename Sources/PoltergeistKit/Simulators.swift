import Foundation

public enum Simulators {
    public struct Device: Hashable, Sendable {
        public var udid: String
        public var name: String
        public var runtime: String
    }

    public struct Failure: LocalizedError {
        public var status: Int32
        public var output: String
        public var errorDescription: String? { output.isEmpty ? "simctl exited with \(status)" : output }
    }

    /// Only call simctl when Xcode is there – otherwise macOS offers to install the developer tools.
    public static var xcodeInstalled: Bool {
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        return apps.contains { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-5" → "iOS 17.5"
    public static func runtimeName(_ key: String) -> String {
        guard let r = key.range(of: "SimRuntime.") else { return key }
        let raw = key[r.upperBound...]
        guard let dash = raw.firstIndex(of: "-") else { return String(raw) }
        let os = raw[..<dash]
        let ver = raw[raw.index(after: dash)...].replacingOccurrences(of: "-", with: ".")
        return "\(os) \(ver)"
    }

    /// Simulators whose runtime is no longer installed.
    public static func parseUnavailable(_ json: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let devices = root["devices"] as? [String: Any] else { return [] }
        var out: [Device] = []
        for (runtime, list) in devices {
            for d in (list as? [[String: Any]]) ?? [] {
                guard (d["isAvailable"] as? Bool) == false, let udid = d["udid"] as? String else { continue }
                out.append(Device(udid: udid, name: d["name"] as? String ?? udid, runtime: runtimeName(runtime)))
            }
        }
        return out
    }

    public static func unavailable() -> [Device] {
        guard xcodeInstalled, let data = try? run(["list", "devices", "--json"]) else { return [] }
        return parseUnavailable(data)
    }

    public static func delete(_ udid: String) throws {
        guard udid.range(of: "^[0-9A-Fa-f-]{36}$", options: .regularExpression) != nil else {
            throw Failure(status: -1, output: "Bad simulator id")
        }
        _ = try run(["delete", udid])
    }

    static func run(_ args: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl"] + args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        var errData = Data()
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errDone.signal()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw Failure(status: p.terminationStatus,
                          output: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        return data
    }
}
