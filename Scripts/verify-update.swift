import CryptoKit
import Foundation

// Public-key verification only. This tool never reads signing credentials.
do {
    guard CommandLine.arguments.count == 4,
          let publicKey = Data(base64Encoded: CommandLine.arguments[2]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "OpenDocUpdate", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: verify-update.swift archive public-key signature"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "OpenDocUpdate", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid update signature"])
    }
    print("Update signature verified")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
