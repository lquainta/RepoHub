import Crypto
import Foundation

/// Verifies GitHub's `X-Hub-Signature-256` header: `sha256=` followed by the
/// hex HMAC-SHA256 of the raw request body, keyed with the webhook secret.
enum WebhookSignature {
    /// Whether `header` is a valid signature of `body`. Compares in constant time.
    static func isValid(_ header: String?, body: Data, secret: String) -> Bool {
        guard let header, header.hasPrefix("sha256="),
            let expected = Data(hex: String(header.dropFirst("sha256=".count)))
        else {
            return false
        }
        let key = SymmetricKey(data: Data(secret.utf8))
        return HMAC<SHA256>.isValidAuthenticationCode(expected, authenticating: body, using: key)
    }

    /// The header value for `body`, for tests and tooling.
    static func sign(_ body: Data, secret: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: Data(secret.utf8)))
        return "sha256=" + Data(mac).map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    /// Decodes lowercase or uppercase hex; `nil` for odd lengths or non-hex characters.
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
