import Foundation

enum PersonaLoaderError: Error, Equatable {
    case resourceNotFound(id: String)
    case missingFrontMatter(id: String)
    case missingField(id: String, field: String)
    case invalidID(id: String)
    case idMismatch(expected: String, actual: String)
}

struct PersonaLoader: Sendable {

    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func parse(_ contents: String, expectedID: String) throws -> Persona {
        guard contents.hasPrefix("---") else {
            throw PersonaLoaderError.missingFrontMatter(id: expectedID)
        }
        // Find the closing fence after the opening one.
        let afterOpen = contents.dropFirst(3)
        guard let closeRange = afterOpen.range(of: "\n---") else {
            throw PersonaLoaderError.missingFrontMatter(id: expectedID)
        }
        let frontMatter = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
        let body = String(afterOpen[closeRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var id: String?
        var version: Int?
        var label: String?

        for rawLine in frontMatter.split(whereSeparator: { $0 == "\n" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "id":      id = value
            case "version": version = Int(value)
            case "label":   label = value
            default:        continue
            }
        }

        guard let resolvedID = id    else { throw PersonaLoaderError.missingField(id: expectedID, field: "id") }
        guard let resolvedVer = version else { throw PersonaLoaderError.missingField(id: expectedID, field: "version") }
        guard let resolvedLabel = label  else { throw PersonaLoaderError.missingField(id: expectedID, field: "label") }
        guard resolvedID == expectedID else {
            throw PersonaLoaderError.idMismatch(expected: expectedID, actual: resolvedID)
        }
        guard Persona.validIDs.contains(resolvedID) else {
            throw PersonaLoaderError.invalidID(id: resolvedID)
        }
        return Persona(id: resolvedID, version: resolvedVer, label: resolvedLabel, systemPrompt: body)
    }

    func load(id: String) throws -> Persona {
        guard Persona.validIDs.contains(id) else {
            throw PersonaLoaderError.invalidID(id: id)
        }
        guard let url = bundle.url(forResource: "\(id)-v1", withExtension: "md", subdirectory: "Personas") else {
            throw PersonaLoaderError.resourceNotFound(id: id)
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parse(contents, expectedID: id)
    }

    func loadAll() throws -> [Persona] {
        try Persona.validIDs.sorted().map { try load(id: $0) }
    }
}
