import Foundation

enum AppConfig {
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static let defaultHost = "https://vocpass.com"

    static var vocPassAPIHost: String {
        CacheService.shared.customAPIHost ?? defaultHost
    }

    static var vocPassAuthHost: String {
        CacheService.shared.customAPIHost ?? defaultHost
    }

    static let discordURL = URL(string: "https://dc.vocpass.com")!
    static let forumURL = URL(string: "https://forum.vocpass.com")!
}