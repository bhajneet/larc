import Foundation

/// Identifies "which network am I on" without SSID — reading Wi-Fi SSID on
/// modern macOS requires Location Services + a provisioning-profile-gated
/// entitlement that doesn't work with ad-hoc/self-signed builds. The default
/// gateway's MAC address is a better fit anyway: it needs no permission, and
/// it's unique per physical router, so two locations sharing an SSID (e.g.
/// both named "Home") are correctly told apart.
enum NetworkFingerprint {
    static func current() -> String? {
        guard let gateway = defaultGatewayIP() else { return nil }
        return arpMAC(for: gateway)
    }

    private static func defaultGatewayIP() -> String? {
        guard let output = run("/sbin/route", ["-n", "get", "default"]) else { return nil }
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                return trimmed
                    .replacingOccurrences(of: "gateway:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func arpMAC(for ip: String) -> String? {
        guard let output = run("/usr/sbin/arp", ["-n", ip]),
              let range = output.range(of: #"([0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}"#, options: .regularExpression)
        else { return nil }
        return String(output[range]).lowercased()
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
