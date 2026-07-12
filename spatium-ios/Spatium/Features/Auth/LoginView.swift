import AuthenticationServices
import CryptoKit
import SwiftUI

struct LoginView: View {
    var onLoggedIn: () -> Void
    /// 앱 진입 게이트로 쓰일 때만 전달됩니다. 전달되면 닫기 버튼 대신
    /// "로그인 없이 둘러보기"가 노출되어 게스트로 계속할 수 있습니다.
    var onContinueAsGuest: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var showSignUp = false
    @State private var pendingSocialSignUp: PendingSocialSignUp?
    @State private var appleRawNonce = ""
    @State private var googleService = GoogleSignInService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    VStack(spacing: 12) {
                        AuthTextField(placeholder: "이메일", text: $email, keyboardType: .emailAddress, textContentType: .username, submitLabel: .next)
                        AuthTextField(placeholder: "비밀번호", text: $password, isSecure: true, textContentType: .password, submitLabel: .go)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let infoMessage {
                        Text(infoMessage)
                            .font(.footnote)
                            .foregroundStyle(SpatiumTheme.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(
                        title: isLoading ? "로그인 중..." : "로그인",
                        systemImage: "arrow.right",
                        action: login
                    )
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Button {
                        // 서버에 비밀번호 재설정 API가 아직 없다. 이메일을 받아 놓고 항상 실패하는
                        // 요청을 보내는 대신, 준비 전임을 바로 안내한다. (서버 제공 시 시트 복원)
                        errorMessage = nil
                        infoMessage = "비밀번호 재설정은 아직 준비 중이에요. Apple/Google 로그인을 이용하거나 새 계정으로 가입해 주세요."
                    } label: {
                        Text("비밀번호를 잊으셨나요?")
                            .font(.footnote)
                            .foregroundStyle(SpatiumTheme.soft)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    dividerWithLabel

                    socialButtons

                    Button {
                        showSignUp = true
                    } label: {
                        Text("계정이 없으신가요? 회원가입")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(SpatiumTheme.accent)
                    }
                    .padding(.top, 4)

                    if let onContinueAsGuest {
                        Button(action: onContinueAsGuest) {
                            Text("로그인 없이 둘러보기")
                                .font(.footnote)
                                .foregroundStyle(SpatiumTheme.soft)
                                .underline()
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("로그인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onContinueAsGuest == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showSignUp) {
                SignUpView(onSignedUp: { signedUpEmail in
                    email = signedUpEmail
                    showSignUp = false
                })
            }
            .sheet(item: $pendingSocialSignUp) { pending in
                SocialSignUpView(pending: pending) {
                    pendingSocialSignUp = nil
                    onLoggedIn()
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            // 앱 공용 로고(큐브). 어두운 배경에서도 크림 타일 덕분에 또렷하게 보인다.
            BrandMark(size: 52)
                .padding(.bottom, 2)
            Text("Spatium에 로그인")
                .font(.title3.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Text("로그인하면 프로젝트가 기기 간에 동기화됩니다.")
                .font(.footnote)
                .foregroundStyle(SpatiumTheme.soft)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    private var dividerWithLabel: some View {
        HStack(spacing: 10) {
            Rectangle().fill(SpatiumTheme.border).frame(height: 1)
            Text("또는")
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
            Rectangle().fill(SpatiumTheme.border).frame(height: 1)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.signIn) { request in
                let rawNonce = Self.randomNonce()
                appleRawNonce = rawNonce
                request.requestedScopes = [.email]
                request.nonce = Self.sha256Hex(rawNonce)
            } onCompletion: { result in
                handleAppleResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

            Button(action: startGoogleSignIn) {
                Label("Google로 계속하기", systemImage: "g.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(SpatiumTheme.elevatedSurface)
                    .foregroundStyle(SpatiumTheme.text)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    // MARK: - 이메일 로그인

    private func login() {
        isLoading = true
        errorMessage = nil
        infoMessage = nil

        Task {
            do {
                // 자동완성/붙여넣기로 섞여 들어오는 앞뒤 공백 때문에 로그인이 실패하지 않게 정리.
                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await AuthService().login(email: trimmedEmail, password: password)
                isLoading = false
                onLoggedIn()
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Apple 로그인

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Apple 로그인에 실패했습니다."
                return
            }
            // 서버가 이 identityToken(JWT)의 서명/iss/aud를 직접 검증하고 email/sub를 얻습니다.
            // 화면 표시용 이메일만 토큰에서 미리 추출합니다.
            let providerEmail = credential.email ?? JWTClaims.email(from: identityToken)
            performSocialLogin(
                provider: .apple,
                idToken: identityToken,
                providerEmail: providerEmail
            )
        case .failure(let error):
            if case ASAuthorizationError.canceled = error { return }
            
            #if DEBUG
            // Error 1000 represents unknown/signing/iCloud error in Simulator or unregistered developer provisioning profiles on real devices.
            // Bypassing to allow local mock authentication testing.
            if (error as NSError).code == 1000 {
                performSocialLogin(
                    provider: .apple,
                    idToken: "mock_apple_id_token",
                    providerEmail: "test.apple@spatium.com"
                )
                return
            }
            #endif

            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Google 로그인

    private func startGoogleSignIn() {
        errorMessage = nil
        Task {
            do {
                let result = try await googleService.signIn()
                performSocialLogin(
                    provider: .google,
                    idToken: result.idToken,
                    providerEmail: result.email
                )
            } catch GoogleSignInError.cancelled {
                // 사용자가 직접 닫은 경우는 에러로 취급하지 않습니다.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 공통: 소셜 로그인 → 미가입이면 추가정보 입력으로 분기

    private func performSocialLogin(
        provider: SocialProvider,
        idToken: String,
        providerEmail: String?
    ) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let request = SocialLoginRequest(provider: provider, idToken: idToken)
                _ = try await AuthService().socialLogin(request)
                isLoading = false
                onLoggedIn()
                dismiss()
            } catch let error as SpatiumAPIError where Self.indicatesUnregistered(error) {
                // 미가입 소셜 계정 → 닉네임을 받아 소셜회원가입으로 유도.
                // 같은 sign-in의 idToken을 그대로 넘겨, 가입 직후 재로그인에 재사용한다.
                isLoading = false
                pendingSocialSignUp = PendingSocialSignUp(
                    provider: provider,
                    idToken: idToken,
                    email: providerEmail
                )
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 소셜로그인 응답에 isNewUser가 없으므로, 서버 에러 코드/상태로 "미가입"을 판별합니다.
    private static func indicatesUnregistered(_ error: SpatiumAPIError) -> Bool {
        if let code = error.serverCode,
           code.contains("NOT_FOUND") || code.contains("SOCIAL_USER") || code.contains("SIGNUP_REQUIRED") {
            return true
        }
        if case let .server(statusCode, _, _) = error, statusCode == 404 {
            return true
        }
        return false
    }

    // MARK: - Apple nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    /// AutoFill / 비밀번호 관리자 연동을 위한 콘텐츠 타입. (HIG "Text fields")
    var textContentType: UITextContentType? = nil
    var submitLabel: SubmitLabel = .return

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .submitLabel(submitLabel)
        .padding(14)
        .background(SpatiumTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
    }
}
