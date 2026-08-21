import SwiftUI

/// Onboarding shared chrome. Expression lives in the product demo, not in backdrop decoration.
/// Dials: standard energy · open density · medium brand · balanced structure · balanced warmth.
enum OnboardingLayout {
    static let horizontalPadding: CGFloat = TabfastDesign.Space.onboardingHorizontal
}

struct OnboardingBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

struct OnboardingIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * TabfastDesign.Radius.tileFraction, style: .continuous)
                .fill(tint)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

extension View {
    func onboardingCard(cornerRadius: CGFloat = TabfastDesign.Radius.onboardingCard) -> some View {
        tabfastCard(cornerRadius: cornerRadius)
    }

    func onboardingReveal(_ index: Int) -> some View {
        modifier(OnboardingReveal(index: index))
    }
}

private struct OnboardingReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 6)
            .onAppear {
                guard !reduceMotion else {
                    revealed = true
                    return
                }
                withAnimation(TabfastDesign.Motion.reveal.delay(Double(index) * 0.04)) {
                    revealed = true
                }
            }
    }
}

struct OnboardingStepHeader: View {
    var systemImage: String?
    var tint: Color = TabfastDesign.ColorToken.accent
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: TabfastDesign.Space.xs) {
            if let systemImage {
                OnboardingIconTile(systemImage: systemImage, tint: tint, size: 40)
            }
            Text(title)
                .font(TabfastDesign.Typography.display)
            Text(subtitle)
                .font(TabfastDesign.Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OnboardingProgressPips: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(pipFill(index))
                    .frame(width: index == current ? 18 : 5, height: 5)
            }
        }
        .animation(TabfastDesign.Motion.selection, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }

    private func pipFill(_ index: Int) -> Color {
        if index == current { return TabfastDesign.ColorToken.accent }
        if index < current { return TabfastDesign.ColorToken.accent.opacity(0.35) }
        return Color.secondary.opacity(0.2)
    }
}

struct WelcomeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TabfastDesign.Typography.callout.weight(.semibold))
                .frame(maxWidth: 220)
        }
        .buttonStyle(.borderedProminent)
        .tint(TabfastDesign.ColorToken.accent)
        .controlSize(.large)
    }
}

struct WelcomeNavigation: View {
    var canGoBack: Bool = false
    var canContinue: Bool = true
    var continueTitle: String = "Continue"
    var disabledHint: String?
    var onBack: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        HStack {
            if canGoBack, let onBack {
                Button("Back", action: onBack)
                    .controlSize(.large)
            }
            Spacer(minLength: 0)
            Button(continueTitle, action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(TabfastDesign.ColorToken.accent)
                .controlSize(.large)
                .disabled(!canContinue)
                .help(canContinue ? "" : (disabledHint ?? ""))
        }
    }
}
