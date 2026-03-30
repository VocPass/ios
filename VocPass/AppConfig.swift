import Foundation

enum AppConfig {
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var vocPassAPIHost: String {
        #if DEBUG
        return "https://vocpass.com"
        #else
        return "https://vocpass.com"
        #endif
    }

    static var vocPassAuthHost: String {
        #if DEBUG
        return "https://vocpass.com"
        #else
        return "https://vocpass.com"
        #endif
    }

    static let discordURL = URL(string: "https://dc.vocpass.com")!
    static let forumURL = URL(string: "https://forum.vocpass.com")!
}