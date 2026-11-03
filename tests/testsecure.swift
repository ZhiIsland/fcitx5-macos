import ApplicationServices

@_cdecl("main")
func main() -> Int {
  var failures = 0
  func expect(_ condition: Bool, _ message: String) {
    if !condition {
      print("FAIL: \(message)")
      failures += 1
    }
  }

  let plain = textFieldKind(
    role: kAXTextFieldRole as String, subrole: nil, subroleStatus: .attributeUnsupported)
  let password = textFieldKind(
    role: kAXTextFieldRole as String, subrole: kAXSecureTextFieldSubrole as String,
    subroleStatus: .success)
  expect(plain == .plain, "Edge's plain field without a subrole must be recognized")
  expect(password == .password, "a real password field must remain protected")
  expect(
    textFieldKind(
      role: kAXTextAreaRole as String, subrole: nil, subroleStatus: .attributeUnsupported)
      == .plain,
    "multiline text areas must recover from stale Secure Input")
  expect(
    textFieldKind(
      role: kAXTextFieldRole as String, subrole: kAXSearchFieldSubrole as String,
      subroleStatus: .success) == .plain,
    "the browser search field must recover from stale Secure Input")
  for status in [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .failure, .noValue] {
    expect(
      textFieldKind(role: kAXTextFieldRole as String, subrole: nil, subroleStatus: status)
        == .unknown,
      "AX error \(status.rawValue) must not authorize Chinese in a password field")
  }
  expect(
    textFieldKind(role: kAXTextFieldRole as String, subrole: "FutureRole", subroleStatus: .success)
      == .unknown,
    "an unrecognized subrole must retain protection")
  expect(
    textFieldKind(role: kAXButtonRole as String, subrole: nil, subroleStatus: .attributeUnsupported)
      == .unknown,
    "non-text focus must not clear password mode")

  // Reproduce the bug: Secure Input stays on through password -> plain ->
  // password focus changes, with the same app and input controller throughout.
  for field in [password, plain, .unknown, plain, password, .unknown] {
    let required = passwordModeRequired(
      passwordOnlyApp: false, secureInputEnabled: true, secureInputOwnedByClient: true,
      focusedTextField: field)
    expect(required == (field != .plain), "focus transition must use the current field")
  }
  for field in [FocusedTextFieldKind.plain, .password, .unknown] {
    expect(
      passwordModeRequired(
        passwordOnlyApp: true, secureInputEnabled: false, secureInputOwnedByClient: false,
        focusedTextField: field),
      "password-only system apps must retain their existing protection")
    expect(
      !passwordModeRequired(
        passwordOnlyApp: false, secureInputEnabled: true, secureInputOwnedByClient: false,
        focusedTextField: field),
      "another app's Secure Input must not force English in this app")
    expect(
      !passwordModeRequired(
        passwordOnlyApp: false, secureInputEnabled: false, secureInputOwnedByClient: true,
        focusedTextField: field),
      "releasing Secure Input must restore the existing behavior")
  }
  print(failures == 0 ? "Secure input regression checks passed" : "\(failures) checks failed")
  return failures == 0 ? 0 : 1
}
