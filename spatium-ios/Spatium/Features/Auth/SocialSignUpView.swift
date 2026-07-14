import SwiftUI

/// 소셜 로그인으로 처음 들어온(미가입) 사용자의 추가정보 입력 화면.
/// 개정 명세(`POST /api/auth/social-users`)에 맞춰 추가 회원 정보를 입력받습니다.
/// 가입 성공 시 토큰이 발급되지 않으므로 다시 소셜 로그인하도록 안내합니다.
struct SocialSignUpView: View {
    let pending: PendingSocialSignUp
    /// 가입 완료 후 호출됩니다. (아직 로그인 상태가 아니며, 재로그인 안내로 이어집니다.)
    var onSignedUp: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var birthDate = Date()
    @State private var gender: Gender = .male
    @State private var termsAgreed = false
    @State private var privacyAgreed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(pending: PendingSocialSignUp, onSignedUp: @escaping () -> Void) {
        self.pending = pending
        self.onSignedUp = onSignedUp
    }

    /// 이메일은 서버가 idToken에서 직접 얻으므로 입력받지 않습니다.
    private var canSubmit: Bool {
        !nickname.isEmpty && termsAgreed && privacyAgreed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    emailField

                    AuthTextField(placeholder: "닉네임", text: $nickname, textContentType: .nickname, submitLabel: .next)

                    DatePicker("생년월일", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .padding(14)
                        .background(SpatiumTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

                    Picker("성별", selection: $gender) {
                        Text("남성").tag(Gender.male)
                        Text("여성").tag(Gender.female)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 10) {
                        AgreementToggle(title: "이용약관에 동의합니다", linkURL: SpatiumLegalLinks.termsOfServiceURL, isOn: $termsAgreed)
                        AgreementToggle(title: "개인정보 수집·이용에 동의합니다", linkURL: SpatiumLegalLinks.privacyPolicyURL, isOn: $privacyAgreed)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(
                        title: isLoading ? "가입 중..." : "가입 완료",
                        systemImage: "person.badge.plus",
                        action: submit
                    )
                    .disabled(isLoading || !canSubmit)
                }
                .padding(20)
            }
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("추가 정보 입력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: pending.provider == .apple ? "apple.logo" : "g.circle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SpatiumTheme.accent)
            Text("\(pending.provider.displayName) 계정으로 처음 오셨네요")
                .font(.headline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Text("가입에 필요한 추가 정보를 입력해 주세요.")
                .font(.footnote)
                .foregroundStyle(SpatiumTheme.soft)
        }
        .padding(.bottom, 4)
    }

    /// 서버가 idToken에서 얻는 이메일을 참고용으로만 보여줍니다. (전송/편집하지 않음)
    @ViewBuilder
    private var emailField: some View {
        if let email = pending.email, !email.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .foregroundStyle(SpatiumTheme.soft)
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(SpatiumTheme.muted)
                Spacer()
                Text("\(pending.provider.displayName) 계정")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SpatiumTheme.soft)
            }
            .padding(14)
            .background(SpatiumTheme.warmPanel)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
    }

    private func submit() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let request = SocialSignUpRequest(
                    provider: pending.provider,
                    idToken: pending.idToken,
                    nickname: nickname,
                    birthDate: DateFormatter.apiDateOnly.string(from: birthDate),
                    gender: gender,
                    termsAgreed: termsAgreed,
                    privacyAgreed: privacyAgreed
                )
                let service = AuthService()
                _ = try await service.socialSignUp(request)

                // 백엔드 소셜 회원가입은 토큰을 반환하지 않으므로, 방금 만든 계정으로 곧바로
                // 소셜 로그인을 한 번 더 호출해 세션(토큰)을 발급받는다. 같은 sign-in의 idToken을
                // 재사용하므로 서버가 동일 계정으로 검증한다.
                let loginRequest = SocialLoginRequest(
                    provider: pending.provider,
                    idToken: pending.idToken
                )
                _ = try await service.socialLogin(loginRequest)

                isLoading = false
                onSignedUp()
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PendingSocialSignUp: Identifiable {
    let id = UUID()
    var provider: SocialProvider
    /// 로그인 시 받은 provider ID Token. 가입 요청과 가입 직후 재로그인에 그대로 사용한다.
    var idToken: String
    /// 화면 표시용 이메일(서버가 실제 이메일은 idToken에서 직접 얻으므로 전송하지 않음).
    var email: String?
}

extension SocialProvider {
    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .kakao: "카카오"
        }
    }
}

struct AgreementToggle: View {
    let title: String
    var linkURL: URL? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? SpatiumTheme.accent : SpatiumTheme.soft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "동의함" : "동의하지 않음")

            Text(title)
                .font(.footnote)
                .foregroundStyle(SpatiumTheme.text)

            Spacer()

            // 동의 전에 내용을 읽을 수 있어야 하므로 원문 링크를 함께 노출한다.
            if let linkURL {
                Link("보기", destination: linkURL)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
            }
        }
    }
}
