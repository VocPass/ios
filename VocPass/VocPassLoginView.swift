//
//  VocPassLoginView.swift
//  VocPass
//

import SwiftUI
import Combine
import AuthenticationServices

struct VocPassLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = VocPassLoginViewModel()

    var body: some View {
        Color.clear
            .onAppear { vm.startLogin() }
            .onChange(of: vm.loginCompleted) { _, completed in
                if completed { dismiss() }
            }
            .onChange(of: vm.cancelled) { _, cancelled in
                if cancelled { dismiss() }
            }
    }
}

@MainActor
class VocPassLoginViewModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var loginCompleted = false
    @Published var cancelled = false

    private var authSession: ASWebAuthenticationSession?

    func startLogin() {
        guard let url = URL(string: "\(AppConfig.vocPassAuthHost)/auth") else { return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "vocpass"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    self.cancelled = true
                    return
                }

                guard let callbackURL else {
                    self.cancelled = true
                    return
                }

                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty {
                    await VocPassAuthService.shared.handleTokenLogin(token: token)
                }
                self.loginCompleted = true
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        authSession = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
