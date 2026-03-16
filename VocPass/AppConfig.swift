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
        return "https://dev.vocpass.com"
        #else
        return "https://vocpass.com"
        #endif
    }
}