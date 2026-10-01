import Foundation

/// A small VT screen reader for the pinned CLI's onboarding and identity header.
/// Input is transient. Neither the raw stream nor authorization URL is persisted.
public enum AntigravityTerminal {
    public static func normalizedEmail(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count <= 254, text.range(of: "^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,}$", options: .regularExpression) != nil else { return nil }
        return text
    }
    public static func identity(in screen: String) -> String? {
        let lines = screen.components(separatedBy: "\n")
        for index in lines.indices where lines[index].contains("Antigravity CLI " + AntigravityCLILocator.version) {
            guard index + 1 < lines.count else { continue }
            // Only the next header row is an identity; arbitrary emails in prompts are ignored.
            let parts = lines[index + 1].split(whereSeparator: { $0.isWhitespace })
            let identities = parts.indices.filter { normalizedEmail(String(parts[$0])) != nil }
            guard identities.count == 1, let position = identities.first,
                  parts[..<position].allSatisfy({ $0.allSatisfy({ !$0.isASCII || $0 == " " }) }) else { continue }
            let suffix = parts.dropFirst(position + 1).joined(separator: " ")
            // Google AI Pro is the suffix observed on both real accounts in the pinned CLI.
            guard suffix.isEmpty || suffix == "(Google AI Pro)" else { continue }
            return normalizedEmail(String(parts[position]))
        }
        return nil
    }

    public static func authenticationURL(in input: String) -> URL? {
        let text = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let expression = try? NSRegularExpression(pattern: "https://[^\\s<>\\u001B]+") else { return nil }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let candidates = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            var candidate = String(text[range])
            // The pinned official TUI wraps its long OAuth URL over physical lines.
            // Only contiguous URI-character lines can continue it; UI prose is excluded.
            let remainder = text[range.upperBound...].components(separatedBy: .newlines)
            for line in remainder.dropFirst() {
                let part = line.trimmingCharacters(in: .whitespaces)
                guard !part.isEmpty,
                      part.range(of: "^[A-Za-z0-9:/?@!$&'()*+,;=._~%#\\[\\]\\-]+$", options: .regularExpression) != nil,
                      !part.hasPrefix("https://") else { break }
                candidate += part
            }
            return candidate
        }
        for candidate in candidates {
            guard let url = URL(string: candidate),
                  let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.port == nil,
                  ["accounts.google.com", "antigravity.google", "auth.antigravity.google"].contains(host),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems,
                  items.contains(where: { $0.name == "response_type" && $0.value == "code" }),
                  items.contains(where: { $0.name == "code_challenge_method" && $0.value == "S256" }),
                  items.contains(where: { $0.name == "code_challenge" && !($0.value ?? "").isEmpty }),
                  items.contains(where: { $0.name == "client_id" && ($0.value ?? "").hasSuffix(".apps.googleusercontent.com") }),
                  items.contains(where: { $0.name == "redirect_uri" && $0.value == "https://antigravity.google/oauth-callback" }) else { continue }
            return url
        }
        return nil
    }

    public static func plainText(_ data: Data) -> String {
        let chars = Array(String(decoding: data, as: UTF8.self))
        var result = "", index = 0
        while index < chars.count {
            let char = chars[index]; index += 1
            guard char == "\u{1B}" else { result.append(char); continue }
            guard index < chars.count else { break }
            let kind = chars[index]; index += 1
            if kind == "[" {
                while index < chars.count {
                    let next = chars[index]; index += 1
                    if let ascii = next.asciiValue, (0x40...0x7E).contains(ascii) { break }
                }
            } else if kind == "]" {
                var osc = ""
                while index < chars.count {
                    let next = chars[index]; index += 1
                    if next == "\u{07}" { break }
                    if next == "\u{1B}", index < chars.count, chars[index] == "\\" { index += 1; break }
                    osc.append(next)
                }
                if let separator = osc.range(of: ";;") { result += osc[separator.upperBound...] }
            }
        }
        return result
    }

    public static func redacted(_ text: String) -> String {
        let expression = try? NSRegularExpression(pattern: "https://[^\\s<>]+")
        let lines = text.components(separatedBy: "\n")
        var hideWrappedURL = false
        return lines.map { line in
            if line.contains("[请点击打开官方认证页面]"), expression?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil {
                hideWrappedURL = true
                return line
            }
            if let expression,
               let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                hideWrappedURL = true
                return String(line[..<range.lowerBound]) + "[请点击打开官方认证页面]"
            }
            if hideWrappedURL {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let isURLContinuation = trimmed.contains("&") || trimmed.contains("=")
                    || trimmed.contains(".googleusercontent.com")
                    || trimmed.range(of: "^[A-Za-z0-9%._~+/:=-]+$", options: .regularExpression) != nil
                if trimmed.isEmpty { return "" }
                if isURLContinuation { return "" }
                hideWrappedURL = false
            }
            return line
        }.joined(separator: "\n")
    }

    public static func screen(_ data: Data, columns: Int = 120, rows: Int = 40) -> String {
        var grid = Array(repeating: Array(repeating: Character(" "), count: columns), count: rows)
        var row = 0, column = 0
        var savedRow = 0, savedColumn = 0
        var normalScreen: ([[Character]], Int, Int)?
        let characters = Array(String(decoding: data, as: UTF8.self))
        var index = 0
        func newline() {
            row += 1
            if row >= rows { grid.removeFirst(); grid.append(Array(repeating: " ", count: columns)); row = rows - 1 }
        }
        while index < characters.count {
            let character = characters[index]; index += 1
            if character == "\u{1B}", index < characters.count {
                let kind = characters[index]; index += 1
                if kind == "[" {
                    var parameters = ""
                    while index < characters.count {
                        let next = characters[index]; index += 1
                        if let ascii = next.asciiValue, (0x40...0x7E).contains(ascii) {
                            let values = parameters.trimmingCharacters(in: CharacterSet(charactersIn: "?=>"))
                                .split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                            let n = max(1, values.first ?? 1)
                            switch next {
                            case "h", "l":
                                if ["?1049", "?1047", "?47"].contains(parameters) {
                                    if next == "h", normalScreen == nil {
                                        normalScreen = (grid, row, column)
                                        grid = Array(repeating: Array(repeating: " ", count: columns), count: rows)
                                        row = 0; column = 0
                                    } else if next == "l", let saved = normalScreen {
                                        grid = saved.0; row = saved.1; column = saved.2; normalScreen = nil
                                    }
                                }
                            case "s": savedRow = row; savedColumn = column
                            case "u": row = savedRow; column = savedColumn
                            case "H", "f": row = min(rows - 1, max(0, n - 1)); column = min(columns - 1, max(0, (values.count > 1 ? max(1, values[1]) : 1) - 1))
                            case "A": row = max(0, row - n)
                            case "B": row = min(rows - 1, row + n)
                            case "E": row = min(rows - 1, row + n); column = 0
                            case "F": row = max(0, row - n); column = 0
                            case "d": row = min(rows - 1, n - 1)
                            case "C": column = min(columns - 1, column + n)
                            case "D": column = max(0, column - n)
                            case "G": column = min(columns - 1, n - 1)
                            case "J":
                                if (values.first ?? 0) == 2 || (values.first ?? 0) == 3 { grid = Array(repeating: Array(repeating: " ", count: columns), count: rows) }
                                else if (values.first ?? 0) == 1 { for r in 0...row { for c in 0..<(r == row ? min(columns, column + 1) : columns) { grid[r][c] = " " } } }
                                else { for r in row..<rows { for c in (r == row ? column : 0)..<columns { grid[r][c] = " " } } }
                            case "K":
                                let mode = values.first ?? 0
                                let range = mode == 2 ? 0..<columns : (mode == 1 ? 0..<min(columns, column + 1) : column..<columns)
                                for c in range { grid[row][c] = " " }
                            default: break
                            }
                            break
                        } else { parameters.append(next) }
                    }
                } else if kind == "7" { savedRow = row; savedColumn = column
                } else if kind == "8" { row = savedRow; column = savedColumn
                } else if kind == "]" {
                    while index < characters.count {
                        let next = characters[index]; index += 1
                        if next == "\u{07}" { break }
                        if next == "\u{1B}", index < characters.count, characters[index] == "\\" { index += 1; break }
                    }
                }
                continue
            }
            switch character {
            case "\r": column = 0
            case "\n", "\r\n": newline(); column = 0
            case "\u{08}": column = max(0, column - 1)
            case "\t": column = min(columns - 1, (column / 8 + 1) * 8)
            default:
                if character.asciiValue.map({ $0 < 32 || $0 == 127 }) == true { continue }
                if column >= columns { column = 0; newline() }
                grid[row][column] = character; column += 1
            }
        }
        return grid.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }
}
