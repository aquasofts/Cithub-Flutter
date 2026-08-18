import Foundation

public struct HTMLNode: Sendable, Equatable {
    public var attributes: String
    public var innerHTML: String

    public func attribute(_ name: String) -> String {
        HTMLParser.attribute(name, in: attributes)
    }

    public func hasAttribute(_ name: String) -> Bool {
        HTMLParser.hasAttribute(name, in: attributes)
    }

    public var text: String { HTMLParser.text(innerHTML) }
}

public enum HTMLParser {
    public static func elements(_ tag: String, in html: String) -> [HTMLNode] {
        captures(
            pattern: #"<\#(tag)\b([^>]*)>(.*?)</\#(tag)\s*>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).map { HTMLNode(attributes: $0[safe: 1] ?? "", innerHTML: $0[safe: 2] ?? "") }
    }

    public static func voidElements(_ tag: String, in html: String) -> [HTMLNode] {
        captures(
            pattern: #"<\#(tag)\b([^>]*)/?>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).map { HTMLNode(attributes: $0[safe: 1] ?? "", innerHTML: "") }
    }

    public static func firstElement(
        _ tag: String,
        in html: String,
        where predicate: (HTMLNode) -> Bool = { _ in true }
    ) -> HTMLNode? {
        elements(tag, in: html).first(where: predicate)
    }

    public static func attribute(_ name: String, in attributes: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let values = captures(
            pattern: #"(?:^|\s)\#(escaped)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
            in: attributes,
            options: [.caseInsensitive]
        ).first else { return "" }
        return values.dropFirst().first(where: { !$0.isEmpty }) ?? ""
    }

    public static func hasAttribute(_ name: String, in attributes: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return attributes.range(
            of: #"(?:^|\s)\#(escaped)(?:\s*=|\s|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    public static func options(in html: String, selectName: String) -> [CoreAcademicTerm] {
        guard let select = elements("select", in: html).first(where: {
            $0.attribute("name").caseInsensitiveCompare(selectName) == .orderedSame
        }) else { return [] }
        return elements("option", in: select.innerHTML).compactMap { option in
            let label = option.text
            guard !label.isEmpty else { return nil }
            return CoreAcademicTerm(
                value: option.attribute("value"),
                label: label,
                selected: option.hasAttribute("selected")
            )
        }
    }

    public static func tableRows(in html: String, id: String? = nil) -> [[String]] {
        let source: String
        if let id,
           let table = elements("table", in: html).first(where: { $0.attribute("id") == id }) {
            source = table.innerHTML
        } else {
            source = html
        }
        return elements("tr", in: source).map { row in
            captures(
                pattern: #"<(?:td|th)\b[^>]*>(.*?)</(?:td|th)\s*>"#,
                in: row.innerHTML,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).map { text($0[safe: 1] ?? "") }
        }
    }

    public static func rowNodes(in html: String, tableID: String? = nil) -> [HTMLNode] {
        let source: String
        if let tableID,
           let table = elements("table", in: html).first(where: { $0.attribute("id") == tableID }) {
            source = table.innerHTML
        } else { source = html }
        return elements("tr", in: source)
    }

    public static func rowCells(_ row: HTMLNode) -> [HTMLNode] {
        captures(
            pattern: #"<(?:td|th)\b([^>]*)>(.*?)</(?:td|th)\s*>"#,
            in: row.innerHTML,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).map { HTMLNode(attributes: $0[safe: 1] ?? "", innerHTML: $0[safe: 2] ?? "") }
    }

    public static func href(in html: String) -> String? {
        voidElements("a", in: html).first(where: { !$0.attribute("href").isEmpty })?.attribute("href")
            ?? captures(
                pattern: #"<a\b([^>]*)>"#, in: html,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).compactMap { values -> String? in
                let value = attribute("href", in: values[safe: 1] ?? "")
                return value.isEmpty ? nil : value
            }.first
    }

    public static func text(_ html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: #"<!--.*?-->"#, with: "", options: [.regularExpression])
        value = value.replacingOccurrences(
            of: #"<(script|style)\b[^>]*>.*?</\1\s*>"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"</(?:p|div|li|tr|h[1-6])\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: [.regularExpression])
        value = decodeEntities(value)
        return value
            .replacingOccurrences(of: #"[\t\r ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func firstCapture(
        _ pattern: String,
        in source: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        captures(pattern: pattern, in: source, options: options).first?[safe: 1]
    }

    public static func captures(
        pattern: String,
        in source: String,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let result = match.range(at: index)
                guard result.location != NSNotFound, let swiftRange = Range(result, in: source) else { return "" }
                return String(source[swiftRange])
            }
        }
    }

    private static func decodeEntities(_ source: String) -> String {
        var result = source
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        named.forEach { result = result.replacingOccurrences(of: $0.key, with: $0.value, options: .caseInsensitive) }
        let matches = captures(pattern: #"&#(x?[0-9a-fA-F]+);"#, in: result)
        for match in matches.reversed() {
            guard let raw = match[safe: 0], let number = match[safe: 1] else { continue }
            let radix = number.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(number.dropFirst()) : number
            if let scalarValue = UInt32(digits, radix: radix), let scalar = UnicodeScalar(scalarValue) {
                result = result.replacingOccurrences(of: raw, with: String(scalar))
            }
        }
        return result
    }
}
