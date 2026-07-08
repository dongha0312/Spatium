import AuthenticationServices
import CryptoKit
import SwiftUI

/// 회원 탈퇴 확인 + 본인 재확인 시트.
/// 서버가 탈퇴 시 본인 재확인을 요구하므로, 일반 계정은 비밀번호로,
/// 소셜 계정은 소셜 재로그인으로 새 idToken을 받아 확인한 뒤 탈퇴를 요청합니다.
///
/// `authMethod`가 nil이면(이 기능 배포 전에 로그인해 둔 세션 등 유형 불명) 비밀번호와
/// 소셜 재인증을 모두 제공해, 소셜 사용자가 입력할 수 없는 비밀번호 화면에 갇히지 않게 합니다.
struct DeleteAccountSheet: View {
    let authMethod: AccountAuthMethod?
    /// 탈퇴 성공(토큰 정리 완료) 후 호출. 필요 시 후처리에 사용합니다.
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var googleService = GoogleSignInService()
    @State private var appleRawNonce: String?

    /// 비밀번호 입력을 노출할지. 일반 계정 또는 유형 불명일 때.
    private var showsPassword: Bool {
        switch authMethod {
        case .local, .none: return true
        case .social: return false
        }
    }

    /// 재인증 버튼을 보여줄 소셜 provider 목록.
    private var socialProviders: [SocialProvider] {
        switch authMethod {
        case .social(let provider): return [provider]
        case .none: return [.apple, .google]   // 유형 불명 → 지원하는 소셜 전부 제시
        case .local: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Text(instruction)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
                .fixedSize(horizontal: false, vertical: true)

            if showsPassword {
                VStack(spacing: 12) {
                    AuthTextField(
                        placeholder: "비밀번호",
                        text: $password,
                        isSecure: true,
                        textContentType: .password
                    )
                    destructiveButton(title: "비밀번호로 탈퇴", disabled: password.isEmpty) {
                        performDelete(password: password, idToken: nil)
                    }
                }
            }

            if showsPassword && !socialProviders.isEmpty {
                dividerOr
            }

            ForEach(socialProviders, id: \.self) { provider in
                socialButton(provider)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("취소") { dismiss() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .disabled(isDeleting)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
    }

    private var detentHeight: CGFloat {
        // 비밀번호(≈140) + 소셜 버튼 개수에 따라 높이를 맞춘다.
        var height: CGFloat = 200
        if showsPassword { height += 130 }
        height += CGFloat(socialProviders.count) * 62
        return height
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(SpatiumTheme.coral)
                .frame(width: 44, height: 44)
                .background(SpatiumTheme.coral.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("정말 탈퇴하시겠어요?")
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("모든 프로젝트와 데이터가 삭제되며 되돌릴 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var instruction: String {
        switch authMethod {
        case .local:
            return "본인 확인을 위해 비밀번호를 입력해 주세요."
        case .social(let provider):
            return "\(provider.displayName) 계정으로 다시 인증하면 탈퇴가 완료됩니다."
        case .none:
            return "본인 확인을 위해 비밀번호를 입력하거나, 가입에 사용한 소셜 계정으로 다시 인증해 주세요."
        }
    }

    private var dividerOr: some View {
        HStack(spacing: 10) {
            Rectangle().fill(SpatiumTheme.border).frame(height: 1)
            Text("또는")
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
            Rectangle().fill(SpatiumTheme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func socialButton(_ provider: SocialProvider) -> some View {
        switch provider {
        case .apple:
            SignInWithAppleButton(.continue) { request in
                let rawNonce = Self.randomNonce()
                appleRawNonce = rawNonce
                request.requestedScopes = [.email]
                request.nonce = Self.sha256Hex(rawNonce)
            } onCompletion: { result in
                handleAppleReauth(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            .disabled(isDeleting)
        case .google:
            destructiveButton(title: "Google(으)로 본인 확인 후 탈퇴", disabled: false) {
                startSocialReauth(.google)
            }
        case .kakao:
            EmptyView()   // 카카오 로그인은 아직 미지원
        }
    }

    private func destructiveButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isDeleting { ProgressView().tint(.white) }
                Text(isDeleting ? "처리 중..." : title)
                    .font(.subheadline.weight(.black))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SpatiumTheme.coral.opacity(disabled || isDeleting ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(disabled || isDeleting)
    }

    // MARK: - Actions

    private func startSocialReauth(_ provider: SocialProvider) {
        errorMessage = nil
        Task {
            do {
                switch provider {
                case .google:
                    let idToken = try await googleService.signIn().idToken
                    performDelete(password: nil, idToken: idToken)
                default:
                    errorMessage = "\(provider.displayName) 계정 탈퇴는 아직 지원되지 않습니다."
                }
            } catch GoogleSignInError.cancelled {
                // 사용자가 직접 취소한 경우는 에러로 표시하지 않습니다.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleAppleReauth(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Apple 본인 확인에 실패했습니다."
                return
            }
            performDelete(password: nil, idToken: identityToken)
        case .failure(let error):
            if case ASAuthorizationError.canceled = error { return }

            #if DEBUG
            // 시뮬레이터/미프로비저닝 환경의 1000 에러는 mock 토큰으로 우회 (로그인 화면과 동일한 처리).
            if (error as NSError).code == 1000 {
                performDelete(password: nil, idToken: "mock_apple_id_token")
                return
            }
            #endif

            errorMessage = error.localizedDescription
        }
    }

    private func performDelete(password: String?, idToken: String?) {
        errorMessage = nil
        isDeleting = true
        Task {
            do {
                if AuthTokenStore.shared.accessToken?.hasPrefix("mock_") == true {
                    // mock 세션(시뮬레이터 로그인)은 서버에 계정이 없으므로 로컬만 정리합니다.
                    AuthTokenStore.shared.clear()
                } else {
                    try await UserService().deleteAccount(password: password, idToken: idToken)
                }
                isDeleting = false
                onDeleted()
                dismiss()
            } catch {
                // 실패를 삼키면 사용자는 탈퇴된 줄 오해하므로 반드시 표시합니다.
                isDeleting = false
                errorMessage = "탈퇴하지 못했어요: \(error.localizedDescription)"
            }
        }
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
