import SwiftUI

struct RootPopoverView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    private let collapsedWidth: CGFloat = 450
    private let expandedWidth: CGFloat = 900
    private let height: CGFloat = 640

    var body: some View {
        ZStack {
            backgroundLayer

            HStack(spacing: 0) {
                PrimaryPanelView(viewModel: viewModel)
                    .frame(width: collapsedWidth, height: height)

                if viewModel.isResultPanelVisible {
                    Divider()
                        .overlay(Color.white.opacity(0.15))

                    ResultPanelView(viewModel: viewModel)
                        .frame(width: collapsedWidth, height: height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(
            width: viewModel.isResultPanelVisible ? expandedWidth : collapsedWidth,
            height: height
        )
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: viewModel.isResultPanelVisible)
    }

    private var backgroundLayer: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Image("DexCraftWatermark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 360, height: 360)
                .opacity(0.3)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                .allowsHitTesting(false)
        }
    }
}
