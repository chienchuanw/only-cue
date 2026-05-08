import Foundation

/// Pure value type describing what happens when the user deletes a `CuePointType`.
/// `make(forTypeID:in:)` returns nil when deletion would leave the project with
/// zero Types (the model invariant `cuePointTypes.count >= 1` per docs/data-model.md).
/// The reassign target is the project's default Type, except when deleting the
/// default itself — in that case the next Type (`cuePointTypes[1]`) absorbs the
/// referenced cues and becomes the new default after the delete lands.
struct TypeDeletionPlan: Equatable {
    let typeID: CuePointType.ID
    let typeName: String
    let referencedCueCount: Int
    let reassignTargetID: CuePointType.ID
    let reassignTargetName: String

    static func make(forTypeID id: CuePointType.ID, in model: ProjectModel) -> TypeDeletionPlan? {
        guard model.cuePointTypes.count > 1 else { return nil }
        guard let target = model.cuePointTypes.first(where: { $0.id == id }) else { return nil }

        let reassignTarget: CuePointType
        if model.cuePointTypes.first?.id == id {
            reassignTarget = model.cuePointTypes[1]
        } else if let defaultType = model.cuePointTypes.first {
            reassignTarget = defaultType
        } else {
            return nil
        }

        let referencedCount = model.items.reduce(0) { acc, item in
            acc + item.cues.filter { $0.typeID == id }.count
        }

        return TypeDeletionPlan(
            typeID: target.id,
            typeName: target.name,
            referencedCueCount: referencedCount,
            reassignTargetID: reassignTarget.id,
            reassignTargetName: reassignTarget.name
        )
    }
}
