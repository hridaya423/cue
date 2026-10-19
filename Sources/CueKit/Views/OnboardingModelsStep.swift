import SwiftUI

extension OnboardingView {
    var modelsControls: some View {
        OnboardingModels(model: model, primary: $stepPrimary) {
            advance()
        }
    }

    var modelsStage: some View {
        VStack(spacing: 18) {
            Image(systemName: "cpu")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white)
            Text("Runs on your Mac. Nothing leaves it.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
