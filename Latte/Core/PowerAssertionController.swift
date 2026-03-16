import IOKit.pwr_mgt
import OSLog

final class PowerAssertionController {
    nonisolated private static let logger = Logger(subsystem: "dev.topscrech.Latte", category: "PowerAssertion")
    
    private var assertionID: IOPMAssertionID = 0
    
    init(name: String) {
        let result = IOPMAssertionCreateWithName(
            "NoDisplaySleepAssertion" as CFString,
            255,
            name as CFString,
            &assertionID
        )
        
        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to create power assertion with result \(result)")
            assertionID = 0
            return
        }
    }
    
    deinit {
        guard assertionID != 0 else { return }
        
        let result = IOPMAssertionRelease(assertionID)
        
        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to release power assertion with result \(result)")
            return
        }
    }
}
