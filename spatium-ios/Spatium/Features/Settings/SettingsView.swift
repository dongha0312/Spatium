import SwiftUI

struct SettingsView: View {
    @Binding var apiEndpoint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "계정 및 API 설정")

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Text("DR")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(
                                LinearGradient(colors: [SpatiumTheme.accent, SpatiumTheme.brown], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dongha Ryu")
                                .font(.headline)
                                .foregroundStyle(SpatiumTheme.text)
                            Text("API 연동 준비 계정")
                                .font(.footnote)
                                .foregroundStyle(SpatiumTheme.soft)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Spring Boot 엔드포인트")
                        .font(.headline)
                        .foregroundStyle(SpatiumTheme.text)

                    TextField("http://서버IP:8080/api/models", text: $apiEndpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.white)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SpatiumTheme.border, lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Text("나중에 인증이 붙으면 이 화면에 토큰, 사용자, 프로젝트 설정을 추가하면 됩니다.")
                        .font(.footnote)
                        .foregroundStyle(SpatiumTheme.soft)
                }
            }
        }
    }
}
