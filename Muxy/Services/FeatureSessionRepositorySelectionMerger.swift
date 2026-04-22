enum FeatureSessionRepositorySelectionMerger {
    static func merge(
        existingRepositories: [FeatureSessionRepositorySelection],
        incomingRepositories: [FeatureSessionRepositorySelection]
    ) -> [FeatureSessionRepositorySelection] {
        var repositoriesByID = Dictionary(uniqueKeysWithValues: existingRepositories.map { ($0.id, $0) })
        var mergedRepositories = existingRepositories

        for incomingRepository in incomingRepositories {
            if let existingRepository = repositoriesByID[incomingRepository.id],
               let existingIndex = mergedRepositories.firstIndex(where: { $0.id == existingRepository.id })
            {
                mergedRepositories[existingIndex] = incomingRepository
                continue
            }

            repositoriesByID[incomingRepository.id] = incomingRepository
            mergedRepositories.append(incomingRepository)
        }

        return mergedRepositories
    }
}
