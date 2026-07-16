import SwiftUI
import UIKit

struct ImgTo3DSegmentationStep: View {
    let isReady: Bool
    let isSegmenting: Bool
    let provider: ImgTo3DSegmentationProvider
    let originalImage: UIImage?
    let segmentedImage: UIImage?
    let result: ImgTo3DSegmentationResult?
    let errorMessage: String?
    @Binding var showOriginal: Bool
    let onRetry: () -> Void

    var body: some View {
        ImgTo3DStepShell(
            systemImage: "wand.and.rays",
            title: isReady ? "배경을 제거했어요" : "가구를 분리하고 있어요",
            description: "입력한 이름을 기준으로 대상을 찾아 투명 배경 PNG로 만듭니다."
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSegmenting {
            ImgTo3DLoadingNote(text: "\(provider.title)가 가구를 분리하고 있어요…")
                .frame(maxHeight: .infinity)
        } else if let sourceImage = showOriginal ? originalImage : segmentedImage {
            VStack(spacing: 14) {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 230)
                    .background(SpatiumTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                Toggle("원본 사진 보기", isOn: $showOriginal)
                    .font(.subheadline.weight(.bold))
                    .tint(SpatiumTheme.accent)
                if let result {
                    resultSummary(result)
                }
            }
        } else if let errorMessage {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(SpatiumTheme.coral)
                    .multilineTextAlignment(.center)
                SecondaryButton(title: "다시 시도", systemImage: "arrow.clockwise", action: onRetry)
            }
        }
    }

    private func resultSummary(_ result: ImgTo3DSegmentationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.segmentedObject)
                .font(.subheadline.weight(.bold))
            if let translated = result.translatedQuery {
                Text("변환된 검색어: \(translated)")
            }
            if let confidence = result.confidence {
                Text("탐지 신뢰도: \(confidence * 100, specifier: "%.1f")%")
            }
        }
        .font(.caption)
        .foregroundStyle(SpatiumTheme.soft)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ImgTo3DGenerationStep: View {
    let progress: Double
    let generated: Bool
    let isGenerating: Bool
    let errorMessage: String?
    let stages: [String]
    let onRetry: () -> Void

    private var currentStage: Int {
        min(Int(progress / (100 / Double(stages.count))), stages.count - 1)
    }

    var body: some View {
        ImgTo3DStepShell(
            systemImage: generated ? "checkmark.seal.fill" : "cube.transparent.fill",
            title: generated ? "3D 모델이 완성됐어요!" : "3D 모델을 만들고 있어요",
            description: generated
                ? "다음 단계에서 모델을 확인하고 보정할 수 있어요."
                : "사진 한 장으로 GLB 모델을 생성하는 중이에요. 잠시만 기다려주세요."
        ) {
            VStack(spacing: 14) {
                progressSegments
                progressSummary
                stageList
                if let errorMessage, !isGenerating {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(SpatiumTheme.coral)
                        .multilineTextAlignment(.center)
                    SecondaryButton(title: "다시 시도", systemImage: "arrow.clockwise", action: onRetry)
                }
            }
        }
    }

    private var progressSegments: some View {
        HStack(spacing: 5) {
            ForEach(stages.indices, id: \.self) { index in
                Capsule()
                    .fill(SpatiumTheme.border.opacity(0.55))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: proxy.size.width * segmentFraction(for: index))
                        }
                    }
                    .frame(height: 7)
            }
        }
        .animation(.linear(duration: 0.07), value: progress)
    }

    private var progressSummary: some View {
        HStack {
            Text(generated ? "모든 단계 완료" : "\(currentStage + 1) / \(stages.count) 단계 · \(stages[currentStage])")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.soft)
                .contentTransition(.opacity)
            Spacer()
            Text("\(Int(progress))%")
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(SpatiumTheme.accent)
                .contentTransition(.numericText())
        }
    }

    private var stageList: some View {
        VStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, label in
                let done = generated || index < currentStage
                let isCurrent = !generated && index == currentStage
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? SpatiumTheme.success : isCurrent ? SpatiumTheme.accent : SpatiumTheme.soft)
                        .contentTransition(.symbolEffect(.replace))
                    Text(label)
                        .font(.subheadline.weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(done || isCurrent ? SpatiumTheme.text : SpatiumTheme.soft)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isCurrent ? SpatiumTheme.elevatedSurface : .clear,
                    in: RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous)
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: done)
            }
        }
        .padding(7)
        .background(SpatiumTheme.warmPanel.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md))
    }

    private func segmentFraction(for index: Int) -> CGFloat {
        let per = 100.0 / Double(stages.count)
        let fraction = (progress - Double(index) * per) / per
        return CGFloat(min(max(fraction, 0), 1))
    }
}
