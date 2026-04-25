import Foundation
import GRDB
import os.log

// MARK: - IntakeValidationError

enum IntakeValidationError: Error {
    case questionTooShort
    case successCriteriaTooShort
    case missingLensTemplate
    case invalidReversibility
    case invalidTimeHorizon
    case invalidSensitivityClass
}

// MARK: - IntakeViewModel

@Observable
@MainActor
final class IntakeViewModel {

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "IntakeViewModel")

    // Valid values
    static let validLensTemplates: [String] = [
        "strategic-bet",
        "make-buy-partner",
        "market-entry",
        "pivot-scale-kill",
        "innovation-portfolio",
        "vendor-technology",
        "org-design",
        "pilot-to-scale"
    ]
    static let validReversibilities: [String] = ["reversible", "semi-reversible", "irreversible"]
    static let validTimeHorizons: [String] = ["weeks", "months", "quarters", "years"]
    static let validSensitivityClasses: [String] = ["public", "sensitive", "confidential"]

    // MARK: Form fields

    var question: String = ""
    var lensTemplate: String = validLensTemplates[0]
    var reversibility: String = "reversible"
    var timeHorizon: String = "months"
    var sensitivityClass: String = "public"
    var successCriteria: String = ""
    var attachmentURLs: [URL] = []
    var attachmentTexts: [String] = []

    // MARK: Submission state

    var isSubmitting: Bool = false
    var submissionError: String? = nil

    // MARK: Validation

    var isValid: Bool {
        questionValidationError == nil &&
        successCriteriaValidationError == nil &&
        !lensTemplate.isEmpty &&
        IntakeViewModel.validLensTemplates.contains(lensTemplate) &&
        IntakeViewModel.validReversibilities.contains(reversibility) &&
        IntakeViewModel.validTimeHorizons.contains(timeHorizon) &&
        IntakeViewModel.validSensitivityClasses.contains(sensitivityClass)
    }

    var questionValidationError: String? {
        if question.count < 20 {
            return "Question must be at least 20 characters."
        }
        return nil
    }

    var successCriteriaValidationError: String? {
        if successCriteria.count < 10 {
            return "Success criteria must be at least 10 characters."
        }
        return nil
    }

    // MARK: Submit

    func submit(db: DatabaseManager) async throws -> Decision {
        // Validate
        guard questionValidationError == nil else { throw IntakeValidationError.questionTooShort }
        guard successCriteriaValidationError == nil else { throw IntakeValidationError.successCriteriaTooShort }
        guard !lensTemplate.isEmpty, IntakeViewModel.validLensTemplates.contains(lensTemplate) else { throw IntakeValidationError.missingLensTemplate }
        guard IntakeViewModel.validReversibilities.contains(reversibility) else { throw IntakeValidationError.invalidReversibility }
        guard IntakeViewModel.validTimeHorizons.contains(timeHorizon) else { throw IntakeValidationError.invalidTimeHorizon }
        guard IntakeViewModel.validSensitivityClasses.contains(sensitivityClass) else { throw IntakeValidationError.invalidSensitivityClass }

        isSubmitting = true
        defer { isSubmitting = false }

        let reversibilityEnum = Reversibility(rawValue: reversibility) ?? .reversible
        let timeHorizonEnum = TimeHorizon(rawValue: timeHorizon) ?? .months
        let sensitivityClassEnum = SensitivityClass(rawValue: sensitivityClass) ?? .public

        let decision = Decision(
            id: UUID().uuidString,
            createdAt: Date(),
            status: .draft,
            question: question,
            lensTemplate: lensTemplate,
            reversibility: reversibilityEnum,
            timeHorizon: timeHorizonEnum,
            sensitivityClass: sensitivityClassEnum,
            successCriteria: successCriteria,
            refinedBrief: nil,
            refinementChatLog: nil
        )

        let isConfidential = sensitivityClass == "confidential"

        try await db.write { db in
            try decision.insert(db)
            if isConfidential {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                    arguments: ["air_gap_enabled", "true"]
                )
            }
        }

        Self.logger.debug("Decision created with id: \(decision.id)")
        return decision
    }
}
