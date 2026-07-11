import SwiftUI

struct SignUpView: View {
    var onSignedUp: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var nickname = ""
    @State private var password = ""
    @State private var birthDate = Date()
    @State private var gender: Gender = .male
    @State private var termsAgreed = false
    @State private var privacyAgreed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !email.isEmpty && !nickname.isEmpty && password.count >= 8 && termsAgreed && privacyAgreed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AuthTextField(placeholder: "이메일", text: $email, keyboardType: .emailAddress, textContentType: .username, submitLabel: .next)
                    AuthTextField(placeholder: "닉네임", text: $nickname, textContentType: .nickname, submitLabel: .next)
                    AuthTextField(placeholder: "비밀번호 (8자 이상)", text: $password, isSecure: true, textContentType: .newPassword, submitLabel: .done)

                    if !password.isEmpty && password.count < 8 {
                        Text("비밀번호는 8자 이상 입력해 주세요.")
                            .font(.caption)
                            .foregroundStyle(SpatiumTheme.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DatePicker("생년월일", selection: $birthDate, displayedComponents: .date)
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
                        AgreementToggle(title: "개인정보처리방침에 동의합니다", linkURL: SpatiumLegalLinks.privacyPolicyURL, isOn: $privacyAgreed)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(
                        title: isLoading ? "가입 중..." : "회원가입",
                        systemImage: "person.badge.plus",
                        action: signUp
                    )
                    .disabled(isLoading || !canSubmit)
                }
                .padding(20)
            }
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("회원가입")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    private func signUp() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await AuthService().signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    birthDate: DateFormatter.apiDateOnly.string(from: birthDate),
                    gender: gender,
                    termsAgreed: termsAgreed,
                    privacyAgreed: privacyAgreed
                )
                isLoading = false
                onSignedUp(email)
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

