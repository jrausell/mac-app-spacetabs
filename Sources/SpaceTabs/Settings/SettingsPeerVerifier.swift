import Darwin
import Foundation
import Security

/// Both endpoints authenticate the exact signed executable bundled on disk.
/// No commands are loaded from files, and no TCP port is opened.
struct SettingsPeerVerifier: @unchecked Sendable {
    let requirement: SecRequirement?
    init(application: URL) {
        var code: SecStaticCode?
        var info: CFDictionary?
        var required: SecRequirement?
        if SecStaticCodeCreateWithPath(application as CFURL, [], &code) == errSecSuccess,
            let code,
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data
        {
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            SecRequirementCreateWithString("cdhash H\"\(hex)\"" as CFString, [], &required)
        }
        requirement = required
    }
    func accepts(_ descriptor: Int32) -> Bool {
        guard let requirement else { return false }
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        return SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess
            && code.map {
                SecCodeCheckValidity($0, [], requirement) == errSecSuccess
            } == true
    }
}
