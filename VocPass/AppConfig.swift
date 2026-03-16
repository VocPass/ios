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
        return "https://vocpass-dev.zeabur.app"
        #else
        return "https://vocpass.zeabur.app"
        #endif
    }
}