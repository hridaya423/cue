import AppKit
import Testing
@testable import CueKit

struct FieldTests {
    private func field(role: String, secure: Bool = false) -> ContextSnapshot.Field {
        var f = ContextSnapshot.Field()
        f.role = role
        f.isSecure = secure
        return f
    }

    @Test func textualRoles() {
        #expect(field(role: "AXTextField").isTextual)
        #expect(field(role: "AXTextArea").isTextual)
        #expect(field(role: "AXComboBox").isTextual)
        #expect(field(role: "AXWebArea").isTextual) // contenteditable surfaces here
    }

    @Test func nonTextualRolesAreBlacklisted() {
        // The blacklist exists so form-fill can't "paste" into a Submit button.
        #expect(!field(role: "AXButton").isTextual)
        #expect(!field(role: "AXLink").isTextual)
        #expect(!field(role: "AXCheckBox").isTextual)
        #expect(!field(role: "AXStaticText").isTextual)
        #expect(!field(role: "").isTextual)
    }

    @Test func secureIsNeverTextual() {
        #expect(!field(role: "AXTextField", secure: true).isTextual)
    }

    @MainActor @Test func passwordFieldsAreFoundBySubrole() {
        let cell = NSSecureTextField().cell
        #expect(cell?.accessibilityRole()?.rawValue == kAXTextFieldRole)
        #expect(cell?.accessibilitySubrole()?.rawValue == kAXSecureTextFieldSubrole)
    }
}
