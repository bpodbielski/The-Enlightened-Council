import Foundation

enum LensTemplateLoaderError: Error, Equatable {
    case resourceNotFound(id: String)
    case decodeFailed(id: String, underlying: String)
    case invalidID(id: String)
}

/// Loads lens template JSON from the app bundle (or a supplied URL for tests).
struct LensTemplateLoader: Sendable {

    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Decode a single template from a JSON `Data` payload.
    func decode(_ data: Data, expectedID: String) throws -> LensTemplate {
        let decoder = JSONDecoder()
        do {
            let template = try decoder.decode(LensTemplate.self, from: data)
            guard template.id == expectedID else {
                throw LensTemplateLoaderError.decodeFailed(
                    id: expectedID,
                    underlying: "id mismatch: expected \(expectedID), got \(template.id)"
                )
            }
            guard LensTemplate.validIDs.contains(template.id) else {
                throw LensTemplateLoaderError.invalidID(id: template.id)
            }
            return template
        } catch let error as LensTemplateLoaderError {
            throw error
        } catch {
            throw LensTemplateLoaderError.decodeFailed(
                id: expectedID,
                underlying: String(describing: error)
            )
        }
    }

    /// Load a single template by ID from the bundle's `LensTemplates/` folder.
    func load(id: String) throws -> LensTemplate {
        guard LensTemplate.validIDs.contains(id) else {
            throw LensTemplateLoaderError.invalidID(id: id)
        }
        guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "LensTemplates") else {
            throw LensTemplateLoaderError.resourceNotFound(id: id)
        }
        let data = try Data(contentsOf: url)
        return try decode(data, expectedID: id)
    }

    /// Load every valid lens template.
    func loadAll() throws -> [LensTemplate] {
        var result: [LensTemplate] = []
        for id in LensTemplate.validIDs.sorted() {
            result.append(try load(id: id))
        }
        return result
    }
}
