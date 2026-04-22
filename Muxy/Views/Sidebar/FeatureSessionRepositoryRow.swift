import SwiftUI

struct FeatureSessionRepositoryRow: View {
    let repository: FeatureSessionRepositorySelection
    let availableBranches: [String]
    let isLoadingBranches: Bool
    let isDisabled: Bool
    let onSelectBaseBranch: (String) -> Void
    let onRefreshBranches: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text("Current: \(repository.currentBranch)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Base branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgMuted)

                BranchPicker(
                    currentBranch: repository.selectedBaseBranch,
                    branches: availableBranches,
                    isLoading: isLoadingBranches,
                    onSelect: onSelectBaseBranch,
                    onRefresh: onRefreshBranches,
                    onCreateBranch: nil,
                    onDeleteBranch: nil
                )
                .disabled(isDisabled)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
