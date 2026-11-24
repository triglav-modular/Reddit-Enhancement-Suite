import SafariServices

// Safari requires a principal class in every web extension. RES never sends a
// native message, so this only answers, empty, if anything ever asks.
@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: [], completionHandler: nil)
    }
}
