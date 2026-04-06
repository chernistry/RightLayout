import Foundation

enum UserIntent: Sendable, Equatable {
    case prose      // Narrative text, safe to correct
    case code       // Code snippets, do NOT autolayout
    case urlOrCommand // URLs or terminal commands, do NOT autolayout
}

/// A lightweight heuristic classifier to detect if the input text is likely code, a URL, or standard prose.
/// Designed for high-speed checks (< 1ms) before expensive ML calls.
actor IntentDetector {
    
    // MARK: - Constants
    
    // Code indications
    private let codeKeywords = Set(["func", "var", "let", "const", "def", "class", "import", "return", "if", "for", "while", "struct", "void", "public", "private", "int", "string", "float"])
    private let codeSymbols = Set(["{", "}", ";", "[", "]", "=", "==", "+=", "=>", "->", "()", "::"])
    private let knownDomainTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov",
        "io", "ai", "app", "dev",
        "co", "uk", "de", "fr", "es", "it", "us", "ca", "au", "cn", "jp", "kr", "br", "in", "ru", "ua", "il",
        "local", "internal"
    ]
    
    // MARK: - API
    
    func detect(text: String, contextAppId: String? = nil) -> UserIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .prose }
        
        // 1. Check for URL/Command pattern
        if isUrlOrCommand(trimmed) {
            return .urlOrCommand
        }
        
        // 2. Check for Code pattern
        if islikelyCode(trimmed) {
            return .code
        }
        
        return .prose
    }
    
    // MARK: - Heuristics
    
    private func isUrlOrCommand(_ text: String) -> Bool {
        // Starts with protocol
        if text.hasPrefix("http:") || text.hasPrefix("https:") || text.hasPrefix("www.") {
            return true
        }
        
        // Starts with common CLI tools
        let cliPrefixes = ["git ", "ssh ", "cd ", "ls ", "mv ", "cp ", "rm ", "docker ", "kubectl ", "npm ", "swift ", "cat ", "grep ", "curl ", "sudo ", "make ", "bundle "]
        for prefix in cliPrefixes {
            if text.hasPrefix(prefix) { return true }
        }
        
        // CLI Flags / Options (e.g. "--verbose", "-m", "-rf", "--name=value")
        if text.hasPrefix("-") {
            // Ensure next char is letter or dash, preventing "- " prose punctuation
            if text.count > 1 {
                let secondChar = text[text.index(text.startIndex, offsetBy: 1)]
                if secondChar == "-" || secondChar.isLetter {
                    return true
                }
            }
        }
        
        // Email address heuristic: contains @ and . after @, no spaces
        if !text.contains(" ") && text.contains("@") {
            let parts = text.split(separator: "@")
            if parts.count == 2 && parts[1].contains(".") {
                return true
            }
        }
        
        // Localhost special case
        if text == "localhost" { return true }
        
        // Domains without protocol (e.g., "api.internal", "foo.co.uk")
        // Must be strict to avoid flagging normal prose or wrong-layout words like "ghbdtn.rfr".
        if !text.contains(" ") && text.contains(".") {
            let parts = text.split(separator: ".")
            if parts.count >= 2 {
                let tld = parts.last!.lowercased()

                // Prefer an allowlist of real/common TLDs for 2-part domains.
                if knownDomainTLDs.contains(tld) {
                    return true
                }

                // For multi-part domains (sub.domain.tld), allow broader detection.
                // Example: "foo.co.uk" (tld="uk") or "a.b.c".
                if parts.count >= 3,
                   tld.count >= 2,
                   tld.count <= 6,
                   tld.allSatisfy({ $0.isLetter }) {
                    return true
                }
            }
        }
        
        // No spaces but has dots/slashes (file path-like) and not a sentence end
        if !text.contains(" ") && (text.contains("/") || text.contains("\\")) {
            return true
        }
        return false
    }
    
    private func islikelyCode(_ text: String) -> Bool {
        // A. Backticks / code spans (Markdown)
        // Important: do NOT treat a single trailing backtick as code, because on RU layouts
        // it can be the "ё" key in wrong-layout typing (Ticket 46).
        if text.contains("```") { return true }
        let backtickCount = text.filter { $0 == "`" }.count
        if backtickCount >= 2 { return true }

        // B. Symbol Density / operators
        // Code has meaningful density of symbols/operators, but short prose tokens may include
        // one symbol (e.g. the RU "ё" key as `) and must not be auto-blocked.
        let codeSymbolCharacters = "{}[]=;`()<>"
        var symbolCount = 0
        for char in text {
            if codeSymbols.contains(String(char)) || codeSymbolCharacters.contains(char) {
                symbolCount += 1
            }
        }

        // High-signal operators even when density is low.
        if text.contains("=") || text.contains("->") || text.contains("=>") || text.contains("::") {
            return true
        }

        let length = Double(max(1, text.count))
        let symbolDensity = Double(symbolCount) / length

        // Require at least 2 symbols before using density to avoid false technical classification
        // on short tokens like "to`".
        if symbolCount >= 2 && symbolDensity > 0.1 {
            return true
        }
        
        // B. CamelCase, PascalCase, snake_case, kebab-case detection
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        var codeTokenCount = 0
        
        for token in tokens {
            // Keyword match
            if codeKeywords.contains(token) {
                codeTokenCount += 2 // Strong signal
            }
            // Assignment
            if token == "=" || token == "==" {
                codeTokenCount += 2
            }
            
            // Identifier Shape Checks
            
            // 1. camelCase: lower...Upper... (no underscore/hyphen)
            // AND PascalCase: Upper...Upper...
            if !token.contains("_") && !token.contains("-") && token.count > 1 {
                 // Check if it has internal uppercase letter (not first, not last preferably, or just internal)
                 // PascalCase: "MyClass" -> Starts Upper, has another Upper inside.
                 // camelCase: "myVar" -> Starts Lower, has Upper inside.
                 
                 let dropFirst = token.dropFirst()
                 
                 // Has at least one uppercase in the rest
                 let hasInternalUpper = dropFirst.contains(where: { $0.isUppercase })
                 let isAllAlpha = token.allSatisfy { $0.isLetter }
                 
                 if isAllAlpha && hasInternalUpper {
                     // Check if it's not all uppercase (CONST) handled separately or acronym
                     let hasLowercase = token.contains(where: { $0.isLowercase })
                     
                     if hasLowercase {
                         // It is mixed case.
                         // Avoid "McDonalds" or proper names if possible, but for strictly correct code, mixed case is a strong signal.
                         // But for prose, "iPhone" is valid.
                         // "iPad", "eBay".
                         // However, protecting "iPhone" from auto-correcting to Russian is actually GOOD.
                         // So detecting it as "code/technical" is safe.
                         codeTokenCount += 1
                     }
                 }
            }
            
            // 3. snake_case: has underscore, not start/end
            if token.contains("_") && !token.hasPrefix("_") && !token.hasSuffix("_") {
                codeTokenCount += 2 // Very strong signal for code (Python, C++, SQL)
            }
            
            // 4. kebab-case: has hyphen, not start/end
            // "user-id" (code), "well-being" (prose).
            // Heuristic: multiple hyphens -> likely code "kebab-case-id"
            // OR mixed with digits -> "user-id-2"
            if token.contains("-") && !token.hasPrefix("-") && !token.hasSuffix("-") {
                let hyphenCount = token.filter { $0 == "-" }.count
                let hasDigits = token.rangeOfCharacter(from: .decimalDigits) != nil
                
                if hyphenCount >= 2 || hasDigits {
                    codeTokenCount += 1
                }
            }
            
            // 5. UPPER_CASE_CONST
            if token.count > 3 && token.allSatisfy({ $0.isUppercase || $0 == "_" }) && token.contains("_") {
                 codeTokenCount += 2
            }
        }
        
        // If single token is clearly code (snake_case/const), capture it
        // Or if we have accumulated signals
        if codeTokenCount >= 2 {
            return true
        }
        
        // Single token camelCase/PascalCase is weaker (1 point), so won't trigger alone?
        // Wait, for "camelCaseVar", codeTokenCount is 1. The test expects .code.
        // We should treat strong camelCase as code if it's the ONLY token (length 1).
        if tokens.count == 1 && codeTokenCount >= 1 {
            return true
        }
        
        return false
    }
}
