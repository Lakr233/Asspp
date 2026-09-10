import Foundation

enum StoreDiagnostics {
    /// NSError userInfo and localized descriptions may contain account names,
    /// signed URLs or Apple response messages. Keep those out of retained logs.
    static func errorSummary(_ error: Error) -> String {
        "type=\(String(describing: type(of: error))) code=\((error as NSError).code)"
    }
}
