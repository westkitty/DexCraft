import SwiftUI

struct RootPopoverView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    private let collapsedWidth: CGFloat = 450
    private let expandedWidth: CGFloat = 900
    private let height: CGFloat = 640

    var body: some View {
        Group {
            if viewModel.isDetachedWindowActive {
                GeometryReader { geometry in
                    content(width: geometry.size.width, height: geometry.size.height, isDetached: true)
                }
                .frame(minWidth: collapsedWidth, minHeight: 520)
            } else {
                let width = viewModel.isResultPanelVisible ? expandedWidth : collapsedWidth
                content(width: width, height: height, isDetached: false)
                    .frame(width: width, height: height)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: viewModel.isResultPanelVisible)
    }

    private var backgroundLayer: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.cyan.opacity(0.07),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()

            Image("DexCraftWatermark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 420, height: 420)
                .opacity(0.36)
                .blendMode(.screen)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat, isDetached: Bool) -> some View {
        ZStack {
            backgroundLayer

            HStack(spacing: 0) {
                PrimaryPanelView(viewModel: viewModel)
                    .frame(width: primaryWidth(totalWidth: width, isDetached: isDetached), height: height)

                if viewModel.isResultPanelVisible {
                    Divider()
                        .overlay(Color.white.opacity(0.15))

                    ResultPanelView(viewModel: viewModel)
                        .frame(width: resultWidth(totalWidth: width, isDetached: isDetached), height: height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func primaryWidth(totalWidth: CGFloat, isDetached: Bool) -> CGFloat {
        guard isDetached else {
            return collapsedWidth
        }

        if !viewModel.isResultPanelVisible {
            return max(collapsedWidth, totalWidth)
        }

        let minPrimary: CGFloat = 340
        let minResult: CGFloat = 340
        var split = floor(totalWidth * 0.48)
        split = max(minPrimary, split)
        split = min(split, totalWidth - minResult)

        if totalWidth < (minPrimary + minResult) {
            split = floor(totalWidth * 0.5)
        }

        return split
    }

    private func resultWidth(totalWidth: CGFloat, isDetached: Bool) -> CGFloat {
        guard viewModel.isResultPanelVisible else { return 0 }
        guard isDetached else { return collapsedWidth }

        let left = primaryWidth(totalWidth: totalWidth, isDetached: true)
        return max(300, totalWidth - left)
    }
}
