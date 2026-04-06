import SwiftUI

extension View {
    func controlContainer(
        in shape: some Shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
    ) -> some View {
        self
            .background {
                shape
                    .fill(Theme.Color.surfaceBase)
                    .overlay {
                        shape
                            .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                    }
            }
    }

    func insetContainer(
        in shape: some Shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
    ) -> some View {
        self
            .background {
                shape
                    .fill(Theme.Color.pageBackgroundSecondary)
                    .overlay {
                        shape
                            .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                    }
            }
    }
}
