// SPDX-License-Identifier: GPL-2.0-only
//
// Injected by codegen/generate-defaults.nu; not part of upstream.

import Foundation
@testable import OmniWM
import XCTest

final class GenerateDefaultsTemplateTests: XCTestCase {
    func testWriteDefaultsTemplate() throws {
        guard let outPath = ProcessInfo.processInfo.environment["OMNIWM_DEFAULTS_OUT"] else {
            throw XCTSkip("OMNIWM_DEFAULTS_OUT is not set; template generation was not requested.")
        }
        let data = try SettingsTOMLCodec.encode(SettingsExport.defaults())
        try data.write(to: URL(fileURLWithPath: outPath))
    }
}
