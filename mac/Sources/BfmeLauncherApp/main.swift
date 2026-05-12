import Foundation
import BfmeKit
import BfmeKitCore
import BfmeHttpInstruments
import BfmeDirectXRuntime
import BfmeWorkshopKit
import BfmeOnlineKit

// The full SwiftUI launcher shell lands in a later feature (FEAT-004). For
// now the executable is a placeholder entry point so the SwiftPM workspace
// builds end-to-end and surfaces a clear, actionable message when run.
print("BFME Workshop launcher (macOS native port) - scaffold build")
print("BfmeKit         : \(BfmeKit.moduleVersion)")
print("BfmeWorkshopKit : \(BfmeWorkshopKit.moduleVersion)")
print("BfmeOnlineKit   : \(BfmeOnlineKit.moduleVersion)")

let survey = DirectXRuntimeManager.surveyHost()
print("DirectX runtime survey: \(survey.summary)")
