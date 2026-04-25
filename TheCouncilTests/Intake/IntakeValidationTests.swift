// IntakeValidationTests.swift
// Validates intake form rules from SPEC §7.3.
// IntakeViewModel is not yet implemented; logic is inline here.

import Foundation
import XCTest

// MARK: - Inline data model

struct IntakeFormData: Sendable {
    var question: String
    var successCriteria: String
    var lensTemplate: String
    var reversibility: String
    var timeHorizon: String
    var sensitivityClass: String
}

// MARK: - Inline validator

struct IntakeFormValidator: Sendable {

    static let validReversibilityValues: Set<String> = [
        "reversible", "semi-reversible", "irreversible"
    ]

    static let validTimeHorizonValues: Set<String> = [
        "weeks", "months", "quarters", "years"
    ]

    static let validSensitivityClassValues: Set<String> = [
        "public", "sensitive", "confidential"
    ]

    func validate(_ form: IntakeFormData) -> Bool {
        guard form.question.count >= 20 else { return false }
        guard form.successCriteria.count >= 10 else { return false }
        guard !form.lensTemplate.isEmpty else { return false }
        guard Self.validReversibilityValues.contains(form.reversibility) else { return false }
        guard Self.validTimeHorizonValues.contains(form.timeHorizon) else { return false }
        guard Self.validSensitivityClassValues.contains(form.sensitivityClass) else { return false }
        return true
    }
}

// MARK: - Tests

final class IntakeValidationTests: XCTestCase {

    private let validator = IntakeFormValidator()

    // A baseline valid form used as a starting point for mutation tests.
    private func validForm() -> IntakeFormData {
        IntakeFormData(
            question: "Should we expand into the European market?",
            successCriteria: "Revenue grows 15% in year one.",
            lensTemplate: "strategic",
            reversibility: "reversible",
            timeHorizon: "quarters",
            sensitivityClass: "sensitive"
        )
    }

    // MARK: question

    func test_intakeValidation_shortQuestion_isInvalid() {
        // 19-character question must fail.
        var form = validForm()
        form.question = String(repeating: "x", count: 19)
        XCTAssertFalse(validator.validate(form), "19-char question should be invalid")

        // 20-character question must pass.
        form.question = String(repeating: "x", count: 20)
        XCTAssertTrue(validator.validate(form), "20-char question should be valid")
    }

    // MARK: successCriteria

    func test_intakeValidation_shortSuccessCriteria_isInvalid() {
        // 9-character success criteria must fail.
        var form = validForm()
        form.successCriteria = String(repeating: "y", count: 9)
        XCTAssertFalse(validator.validate(form), "9-char success_criteria should be invalid")

        // 10-character success criteria must pass.
        form.successCriteria = String(repeating: "y", count: 10)
        XCTAssertTrue(validator.validate(form), "10-char success_criteria should be valid")
    }

    // MARK: lensTemplate

    func test_intakeValidation_emptyLens_isInvalid() {
        var form = validForm()
        form.lensTemplate = ""
        XCTAssertFalse(validator.validate(form), "Empty lens_template should be invalid")

        form.lensTemplate = "strategic"
        XCTAssertTrue(validator.validate(form), "Non-empty lens_template should be valid")
    }

    // MARK: reversibility

    func test_intakeValidation_invalidReversibility_isInvalid() {
        var form = validForm()
        form.reversibility = "maybe"
        XCTAssertFalse(validator.validate(form), "'maybe' is not a valid reversibility value")

        form.reversibility = "reversible"
        XCTAssertTrue(validator.validate(form), "'reversible' should be valid")

        form.reversibility = "semi-reversible"
        XCTAssertTrue(validator.validate(form), "'semi-reversible' should be valid")

        form.reversibility = "irreversible"
        XCTAssertTrue(validator.validate(form), "'irreversible' should be valid")
    }

    // MARK: combined

    func test_intakeValidation_allFieldsValid_isValid() {
        let form = validForm()
        XCTAssertTrue(validator.validate(form), "A fully valid form must pass validation")
    }
}
