import Foundation

enum AppConfig {
    static var vocPassAPIHost: String {
        #if DEBUG
        return "https://vocpass-dev.zeabur.app"
        #else
        return "https://vocpass.zeabur.app"
        #endif
    }
}