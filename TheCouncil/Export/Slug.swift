import Foundation

// MARK: - Slug helper
//
// SPEC §6.10 file naming:
//   [slugified-question]-[YYYY-MM-DD].md
//   [slugified-question]-[YYYY-MM-DD].pdf
//
// Slug rules: lowercase, spaces → hyphens, strip special characters,
// truncate to 60 chars.

enum Slug {

    static let maxLength = 60

    /// Produces a filesystem-safe slug from arbitrary input.
    /// Collapses runs of non-alphanumeric characters to a single hyphen.
    /// Strips leading/trailing hyphens before truncating to 60 chars.
    static func slugify(_ raw: String) -> String {
        // 1. Lowercase + Unicode-folding for accents.
        let folded = raw.folding(options: .diacriticInsensitive, locale: .current).lowercased()

        // 2. Replace each non-ASCII-alphanumeric character with a hyphen.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        var scratch = ""
        scratch.reserveCapacity(folded.count)
        var lastWasHyphen = false
        for scalar in folded.unicodeScalars {
            if allowed.contains(scalar) {
                scratch.append(Character(scalar))
                lastWasHyphen = false
            } else if !lastWasHyphen {
                scratch.append("-")
                lastWasHyphen = true
            }
        }

        // 3. Trim leading/trailing hyphens.
        let trimmed = scratch.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // 4. Truncate to maxLength, then trim trailing hyphens again
        //    (in case the cut landed mid-separator).
        if trimmed.count <= maxLength { return trimmed }
        let cut = trimmed.prefix(maxLength)
        return String(cut).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Combines `slugify(question)` with the verdict date as `YYYY-MM-DD`.
    /// Returns the bare basename (no extension).
    static func filename(question: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return "\(slugify(question))-\(formatter.string(from: date))"
    }
}
