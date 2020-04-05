import CryptoCore
import BigInt

public protocol KeyDerivator {
    @inlinable
    static func hmac<H: HashFunction>(_ hashFunction: H.Type, key: Data, data: Data) -> Result<Data, KeyDerivatorError>
    
    @inlinable
    static func secp256k_1(data: Data, compressed: Bool) -> Result<Data, KeyDerivatorError>
    
    @inlinable
    static func hash160(data: Data) -> Result<Data, KeyDerivatorError>
}

extension KeyDerivator {
    @inlinable @inline(__always)
    public static func hmac<H>(_ hashFunction: H.Type, key: Data, data: Data) -> Result<Data, KeyDerivatorError> where H : HashFunction {
        .success({
            var hmac = HMAC<H>(key: SymmetricKey(data: key))
            hmac.update(data: data)
            return Data(hmac.finalize())
            }()
        )
    }

    @inlinable @inline(__always)
    public static func secp256k_1(data: Data, compressed: Bool) -> Result<Data, KeyDerivatorError> {
        _GeneratePublicKey(data: data, compressed: compressed)
    }
    
    @inlinable @inline(__always)
    public static func hash160(data: Data) -> Result<Data, KeyDerivatorError> {
        .success(
            RIPEMD160.hash(data: {
                var sha256 = SHA256()
                sha256.update(data: data)
                return Data(sha256.finalize())
            }())
        )
    }
}

/**
 * The total number of possible extended keypairs is almost 2512, but the
 * produced keys are only 256 bits long, and offer about half of that in
 * terms of security. Therefore, master keys are not generated directly,
 * but instead from a potentially short seed value.
 *
 * - BIP-0032 : https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#master-key-generation
 */
public extension KeyDerivator {
    static func masterKeyData(fromHexString hexString: String) -> Result<(key: Data, chainCode: Data), KeyDerivatorError> {
        Result(catching: { try Data(hexString: hexString) }).masterKeyData(using: Self.self)
    }
    
    static func masterKeyData(fromSeed data: Data) -> Result<(key: Data, chainCode: Data), KeyDerivatorError> {
        hmac(SHA512.self, key: .BitcoinKeyData, data: data).map { ($0[..<32], $0[32...]) }
    }
}

public extension KeyDerivator {
    static func rootKey(fromHexString hexString: String, version network: Network) -> Result<ExtendedKey, KeyDerivatorError> {
        masterKeyData(fromHexString: hexString).flatMap { rootKey(fromMasterKey: $0, version: network) }
    }
    
    static func rootKey(fromSeed data: Data, version network: Network) -> Result<ExtendedKey, KeyDerivatorError> {
        masterKeyData(fromSeed: data).flatMap { rootKey(fromMasterKey: $0, version: network) }
    }

    static func rootKey(fromMasterKey masterKey: (key: Data, chainCode: Data), version network: Network) -> Result<ExtendedKey, KeyDerivatorError> {
        Result(catching: { try ExtendedKey(masterKey: masterKey, version: network) }).mapError { .keyDerivationError($0) }
    }
}

/**
 *
 */
public enum KeyDerivatorError: Swift.Error {
    case keyDerivationError(Swift.Error)
    case keyDerivationMissingImplementation
    case keyDerivationFailed(_ description: String)
    case keyDerivationParsingPublicKeyFailed(publicKey: Data)
}

//------------------------------------------------------------------------------
extension Data {
    /**
     * `public` is used to allow functions to be inlined.
     */
    public static let BitcoinKeyData = try! Data(hexString: "426974636f696e2073656564") // key = "Bicoin seed"
}

//------------------------------------------------------------------------------
extension Result where Success == Data {
    fileprivate func masterKeyData(using keyDerivator: KeyDerivator.Type = DefaultKeyDerivator.self) -> Result<(key: Data, chainCode: Data), KeyDerivatorError> {
        mapError { .keyDerivationError($0) }
        .flatMap { keyDerivator.hmac(SHA512.self, key: .BitcoinKeyData, data: $0) }
            .map { ($0[..<32], $0[32...]) }
    }
}

/**
 * 65-bytes if `compressed`; 33-bytes, otherwise.
 */
@usableFromInline
func _GeneratePublicKey(data: Data, compressed: Bool) -> Result<Data, KeyDerivatorError> {
    guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)) else {
        return .failure(.keyDerivationFailed("Failed to generate a public key: invalid context."))
    }
    
    defer { secp256k1_context_destroy(ctx) }
    
    var privateKey: [UInt8] = Array(data)
    guard secp256k1_ec_seckey_verify(ctx, &privateKey) == 1 else {
        return .failure(.keyDerivationFailed("Failed to generate a public key: private key is not valid."))
    }
    
    let publicKey = UnsafeMutablePointer<secp256k1_pubkey>.allocate(capacity: 1)
    guard secp256k1_ec_pubkey_create(ctx, publicKey, privateKey) == 1 else {
        return .failure(.keyDerivationFailed("Failed to generate a public key: public key could not be created."))
    }

    let compress       = compressed ? UInt32(SECP256K1_EC_COMPRESSED) : UInt32(SECP256K1_EC_UNCOMPRESSED)
    let outputByteSize = compressed ? 33 : 65
    var publicKeyBytes = [UInt8](repeating: 0, count: outputByteSize)
    var publicKeyLen   = publicKeyBytes.count

    guard secp256k1_ec_pubkey_serialize(ctx, &publicKeyBytes, &publicKeyLen, publicKey, compress) == 1 else {
        return .failure(.keyDerivationFailed("Failed to generate a public key: public key could not be serialized."))
    }
    
    return .success(Data(publicKeyBytes))
}

//------------------------------------------------------------------------------
#if canImport(CryptoKit)
import CryptoKit
/**
 * An implementation of `KeyDerivator` using _CryptoKit_.
 */
public struct CryptoKitKeyDerivator: KeyDerivator {
    /**
     * _CryptoKit_ & _SwiftCrypto_ share the same APIs.
     */
}
#endif

//------------------------------------------------------------------------------
#if canImport(Crypto)
import Crypto
/**
 * An implementation of `KeyDerivator` using _SwiftCrypto_.
 */
public struct SwiftCryptoKeyDerivator: KeyDerivator {
    /**
     * _CryptoKit_ & _SwiftCrypto_ share the same APIs.
     */
}
#endif

//------------------------------------------------------------------------------
/**
 * Key derivator stub with a missing implementations. Guaranteed to fail.
 */
public struct DummyKeyDerivator: KeyDerivator {
    @inlinable @inline(__always)
    public static func hmac(key: Data = .BitcoinKeyData, data: Data) -> Result<Data, KeyDerivatorError> {
        .failure(.keyDerivationMissingImplementation)
    }
    
    public static func secp256k_1(data: Data, compressed: Bool) -> Result<Data, KeyDerivatorError> {
        .failure(.keyDerivationMissingImplementation)
    }
    
    @inlinable @inline(__always)
    public static func hash160(data: Data) -> Result<Data, KeyDerivatorError> {
        .failure(.keyDerivationMissingImplementation)
    }
}

//------------------------------------------------------------------------------
#if     canImport(CryptoKit)
public typealias DefaultKeyDerivator = CryptoKitKeyDerivator
#elseif canImport(Crypto)
public typealias DefaultKeyDerivator = SwiftCryptoKeyDerivator
#else
public typealias DefaultKeyDerivator = DummyKeyDerivator
#endif
