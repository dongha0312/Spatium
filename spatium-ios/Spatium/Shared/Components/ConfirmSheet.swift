import SwiftUI

/// 파괴적 작업 확인 팝업 — 시스템 alert 대신 앱 톤으로 통일한 하단 시트.
/// 회원 탈퇴, 삭제 등 되돌릴 수 없는 작업 앞에 공용으로 사용합니다.
struct ConfirmSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    var confirmSystemImage: String = "trash"
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(SpatiumTheme.coral)
                    .frame(width: 44, height: 44)
                    .background(SpatiumTheme.coral.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Text("취소")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(SpatiumTheme.warmPanel)
                        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(SpatiumTheme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                }
                .buttonStyle(.pressable)

                Button {
                    dismiss()
                    onConfirm()
                } label: {
                    Label(confirmTitle, systemImage: confirmSystemImage)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(SpatiumTheme.coral)
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
    }
}
