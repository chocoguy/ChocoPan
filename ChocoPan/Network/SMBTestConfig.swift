import Foundation

struct SMBTestFile: Identifiable, Hashable {
    let title: String
    let path: String

    var id: String { path }
}


enum SMBTestConfig {
    static let host = "192.168.1.153"
    static let share = "anime"
    static let username = "chocoguy"
    static let password = ""

    static var serverURL: URL {
        URL(string: "smb://\(host)")!
    }

    static var credential: URLCredential {
        URLCredential(user: username, password: password, persistence: .forSession)
    }

    static let files: [SMBTestFile] = [
        SMBTestFile(
            title: "Lucky Star 04",
            path: "Lucky Star/Moe LuckyStar 04 BD 1080p FLAC.mp4"
        ),
        SMBTestFile(
            title: "Needy Girl Overdose 07",
            path: "Needy Girl Overdose/[SubsPlease] NEEDY GIRL OVERDOSE - 07 (1080p) [A91DF9F8].mkv"
        ),
    ]
}
