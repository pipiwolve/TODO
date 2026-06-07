import Foundation

public enum PlanningParser {
    public enum Error: Swift.Error, Equatable {
        case invalidPayload
    }

    public static func parse(_ json: String) throws -> PlanningResult {
        guard let data = json.data(using: .utf8) else {
            throw Error.invalidPayload
        }

        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(PlanningResult.self, from: data)
            guard !result.tasks.isEmpty,
                  result.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            else {
                throw Error.invalidPayload
            }
            return result
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidPayload
        }
    }
}
