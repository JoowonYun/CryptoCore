import CryptoCore

/**
 * A list of words which can generate a private key.
 */
public struct Mnemonic: Equatable {
    /// The list of words as a single sentence.
    public private(set) var phrase :String = ""

    /// The list of words.
    public var words :[String] {
        phrase.split(separator: " ").map(String.init)
    }
    
    /**
     * Create a mnemonic from a list of `words`.
     *
     * - parameter words: An array of words.
     */
    public init?<Words: Collection>(words: Words) where Words.Element: StringProtocol {
        guard Strength.wordCounts.contains(words.count) else {
            return nil
        }
        self.phrase = words.joined(separator: " ")
    }

    /**
     * Create a mnemonic, generating _entropy_ based on `strength`, with phrase_
     * pulled from the `vocabulary` list.
     *
     * - parameter strength
     * - parameter vocabulary
     */
    public init(strength: Strength, in vocabulary: WordList = .english) throws {
        self = try Mnemonic(entropy: strength, in: vocabulary)
    }
    
    /**
     * Create a mnemonic from a pre-computed `entropy`, with phrase_ pulled from
     * the `vocabulary` list.
     *
     * - parameter entropy
     * - parameter vocabulary
     */
    public init<Entropy: EntropyGenerator>(entropy: Entropy, in vocabulary: WordList = .english) throws {
        self = Mnemonic(words: try vocabulary.randomWords(withEntropy: entropy))!
    }

    /**
     * Create the mnemonic's private key (seed).
     *
     * - warning: Calling this function can take some time. Avoid calling
     *            this function from the main thread, when possible.
     *
     * **BIP39**:
     *
     * https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki#from-mnemonic-to-seed
     *
     * - parameter passphrase: Associates a secret (for extra security).
     * - parameter derivator: The `SeedDerivator` used to derived the seed.
     *
     * - returns: A _result_ with the seed's bytes, or an `Error`.
     */
    public func seed(passphrase: String = "", derivator: SeedDerivator.Type = DefaultSeedDerivator.self) -> Result<Data, SeedDerivatorError> {
        derivator.derivedSeed(fromPassword: self.phrase, salt: "mnemonic" + passphrase)
    }
}

extension Mnemonic {
    /**
     * An `EntropyGenerator` based on bit-sizes.
     */
    public enum Strength: Int, EntropyGenerator {
        case weakest   = 128  // 12 words
        case weak      = 160  // 15 words
        case medium    = 192  // 18 words
        case strong    = 224  // 21 words
        case strongest = 256  // 24 words
        
        /// A set of all `Strength` values.
        public static var allValues: [Strength] {
            [
                .weakest,
                .weak,
                .medium,
                .strong,
                .strongest,
            ]
        }
        
        fileprivate static var wordCounts: [Int] {
            [ 12, 15, 18, 21, 24 ]
        }

        /**
         * Generates _entropy_ data.
         */
        public func entropy() -> Result<Data, Swift.Error> {
            Result { try Data.randomBytes(rawValue / 8) }
        }
    }
}