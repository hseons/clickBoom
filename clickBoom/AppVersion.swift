import Foundation

/// GitHub Release 与应用版本的逐段比较，预发布版本低于同号正式版。
enum AppVersionComparator {
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteVersion = parsedVersion(remote)
        let localVersion = parsedVersion(local)
        for index in 0..<max(remoteVersion.numbers.count, localVersion.numbers.count) {
            let remoteNumber = index < remoteVersion.numbers.count
                ? remoteVersion.numbers[index]
                : 0
            let localNumber = index < localVersion.numbers.count
                ? localVersion.numbers[index]
                : 0
            if remoteNumber != localNumber {
                return remoteNumber > localNumber
            }
        }

        switch (remoteVersion.prerelease, localVersion.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return false
        case (nil, .some):
            return true
        case let (.some(remoteTag), .some(localTag)):
            return remoteTag > localTag
        }
    }

    private nonisolated static func parsedVersion(
        _ rawVersion: String
    ) -> (numbers: [Int], prerelease: String?) {
        let withoutPrefix = rawVersion.hasPrefix("v")
            ? String(rawVersion.dropFirst())
            : rawVersion
        let parts = withoutPrefix.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let numbers = parts[0].split(separator: ".").map { component in
            Int(component.prefix { $0.isNumber }) ?? 0
        }
        let prerelease = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        return (numbers, prerelease)
    }
}
