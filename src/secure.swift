import AppKit
import ApplicationServices
import Carbon
import IOKit

enum FocusedTextFieldKind {
  case plain
  case password
  case unknown
}

func passwordModeRequired(
  passwordOnlyApp: Bool, secureInputEnabled: Bool, secureInputOwnedByClient: Bool,
  focusedTextField: FocusedTextFieldKind
) -> Bool {
  if passwordOnlyApp {
    return true
  }
  return secureInputEnabled && secureInputOwnedByClient && focusedTextField != .plain
}

// Only a positively identified, focused plain text field can override Secure Input.
// Unknown subroles and accessibility failures retain the password protection.
func textFieldKind(role: String?, subrole: String?, subroleStatus: AXError)
  -> FocusedTextFieldKind
{
  if subroleStatus == .success && subrole == (kAXSecureTextFieldSubrole as String) {
    return .password
  }
  guard role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) else {
    return .unknown
  }
  switch subroleStatus {
  case .success:
    return subrole == (kAXSearchFieldSubrole as String) ? .plain : .unknown
  case .attributeUnsupported:
    return .plain
  default:
    return .unknown
  }
}

func focusedTextFieldKind(in appId: String) -> FocusedTextFieldKind {
  // Do not prompt for access or read AXValue, selected text, or the document.
  guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
    app.bundleIdentifier == appId
  else {
    return .unknown
  }
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  // This is on the key-event path. A hung browser must not hang the input method.
  guard AXUIElementSetMessagingTimeout(appElement, 0.01) == .success else {
    return .unknown
  }
  // Chromium activates native web accessibility when an assistive client reads
  // the application's role. Without this, web fields may be missing even though
  // the native address bar is accessible. This reads metadata and changes no settings.
  var appRole: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &appRole) == .success,
    appRole as? String == (kAXApplicationRole as String)
  else {
    return .unknown
  }
  var focusedValue: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(
      appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
    let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
  else {
    return .unknown
  }
  let focusedElement = focusedValue as! AXUIElement
  guard AXUIElementSetMessagingTimeout(focusedElement, 0.01) == .success else {
    return .unknown
  }
  var pid: pid_t = 0
  guard AXUIElementGetPid(focusedElement, &pid) == .success, pid == app.processIdentifier else {
    return .unknown
  }
  var focused: CFTypeRef?
  var role: CFTypeRef?
  var subrole: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(focusedElement, kAXFocusedAttribute as CFString, &focused)
      == .success,
    (focused as? Bool) == true,
    AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role) == .success
  else {
    return .unknown
  }
  let subroleStatus = AXUIElementCopyAttributeValue(
    focusedElement, kAXSubroleAttribute as CFString, &subrole)
  // Revalidate focus after the cross-process calls. Never reuse field metadata
  // across events: Edge can change between a plain and password field in one IMK session.
  var currentFocused: CFTypeRef?
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
    AXUIElementCopyAttributeValue(
      appElement, kAXFocusedUIElementAttribute as CFString, &currentFocused) == .success,
    let currentFocused, CFEqual(focusedElement, currentFocused)
  else {
    return .unknown
  }
  return textFieldKind(
    role: role as? String, subrole: subrole as? String, subroleStatus: subroleStatus)
}

// Translated from https://github.com/espanso/espanso
// The return value is not guaranteed accurate. To reproduce, execute
// import Carbon
// EnableSecureEventInput()
// in swift repl, then this function returns terminal app's pid.
// However, after Ctrl+Cmd+Q and re-login, it returns com.apple.loginwindow's pid.
func getSecureInputProcessPID() -> Int32? {
  let rootService = IORegistryGetRootEntry(kIOMainPortDefault)
  guard rootService != 0 else { return nil }

  defer { IOObjectRelease(rootService) }
  if let cfConsoleUsers = IORegistryEntryCreateCFProperty(
    rootService,
    "IOConsoleUsers" as CFString,
    kCFAllocatorDefault,
    0
  )?.takeRetainedValue() as? [Any] {
    for user in cfConsoleUsers {
      if let userDict = user as? [String: Any],
        let secureInputPID = userDict["kCGSSessionSecureInputPID"] as? NSNumber
      {
        return secureInputPID.int32Value
      }
    }
  }
  return nil
}
