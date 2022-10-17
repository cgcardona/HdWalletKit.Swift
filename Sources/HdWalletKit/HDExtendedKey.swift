import Foundation
import HsCryptoKit
import HsExtensions

public enum HDExtendedKey {
    static let nonHardened = 81

    case `private`(key: HDPrivateKey)
    case `public`(key: HDPublicKey)

    public init(extendedKey: String) throws {
        let version = try HDExtendedKey.version(extendedKey: extendedKey)
        // extended key length : 4 + 1 + 4 + 4 + 32 + (HARDENED! Private has zero-bite 1) + 32 + 4
        let shift = version.isPublic ? 0 : 1

        let data = Base58.decode(extendedKey)
        guard data.count == HDExtendedKey.nonHardened + shift else {
            throw ExtendedKeyParsingError.wrongKeyLength
        }

        let derivedType = DerivedType(depth: data[4])
        guard derivedType != .bip32 else {
            throw ExtendedKeyParsingError.wrongDerivedType
        }

        let checksumIndex = 77 + shift
        let checksum: Data = data[checksumIndex..<(checksumIndex + 4)]
        guard Data(Crypto.doubleSha256(data[0..<checksumIndex]).prefix(4)) == checksum else {
            throw ExtendedKeyParsingError.invalidChecksum
        }

        let depth: UInt8 = data[4]
        let fingerprint: UInt32 = data[5..<9].hs.to(type: UInt32.self).bigEndian
        let childIndex: UInt32 = data[9..<13].hs.to(type: UInt32.self).bigEndian
        let chainCode: Data = data[13..<45]
        // for private 45 byte = 0

        let raw: Data = data[(45 + shift)..<78]

        if version.isPublic {
            self = .public(key:
                    HDPublicKey(
                            raw: raw,
                            chainCode: chainCode,
                            xPubKey: version.rawValue,
                            depth: depth,
                            fingerprint: fingerprint,
                            childIndex: childIndex)
            )
        } else {
            self = .private(key:
                    HDPrivateKey(
                            privateKey: raw,
                            chainCode: chainCode,
                            xPrivKey: version.rawValue,
                            depth: depth,
                            fingerprint: fingerprint,
                            childIndex: childIndex)
            )
        }
    }

    public var derivedType: DerivedType {
        switch self {
        case .private(let key): return DerivedType(depth: key.depth)
        case .public(let key): return DerivedType(depth: key.depth)
        }
    }

}

public extension HDExtendedKey {

    var data: Data {
        switch self {
        case .private(let key): return key.data
        case .public(let key): return key.data
        }
    }

    var info: KeyInfo {
        let xKey: UInt32
        let depth: UInt8

        switch self {
        case .private(let key):
            xKey = key.xPrivKey
            depth = key.depth
        case .public(let key):
            xKey = key.xPubKey
            depth = key.depth
        }

        let version = HDExtendedKeyType(rawValue: xKey) ?? .xprv
        return KeyInfo(mnemonicDerivation: version.mnemonicDerivation, coinType: version.coinType, derivedType: DerivedType(depth: depth))
    }

    static func version(extendedKey: String) throws -> HDExtendedKeyType {
        let version = String(extendedKey.prefix(4))
        guard let keyType = HDExtendedKeyType(string: version) else {
            throw ParsingError.wrongVersion
        }

        return keyType
    }

}

public extension HDExtendedKey {

    //master key depth == 0, account depth = "m/purpose'/coin_type'/account'" = 3, all others is custom
    enum DerivedType {
        case bip32
        case master
        case account

        init(depth: UInt8) {
            switch depth {
            case 0: self = .master
            case 3: self = .account
            default: self = .bip32
            }
        }
    }

    struct KeyInfo {
        let mnemonicDerivation: MnemonicDerivation
        let coinType: ExtendedKeyCoinType
        let derivedType: DerivedType
    }

    enum ParsingError: Error {
        case wrongVersion
        case wrongKeyLength
        case invalidChecksum
    }

}
