import Foundation

struct EngineSettings: Codable, Equatable {
    var threads: Int
    var hashMB: Int
    var multiPV: Int
    var depth: Int

    static var `default`: EngineSettings {
        EngineSettings(
            threads: max(ProcessInfo.processInfo.processorCount / 3, 2),
            hashMB: 256,
            multiPV: 3,
            depth: 30
        )
    }

    static let threadsRange = 1...ProcessInfo.processInfo.processorCount
    static let hashRange = 16...4096
    static let multiPVRange = 1...5
    static let depthRange = 10...80

    init(threads: Int, hashMB: Int, multiPV: Int, depth: Int = 30) {
        self.threads = threads
        self.hashMB = hashMB
        self.multiPV = multiPV
        self.depth = depth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = try container.decode(Int.self, forKey: .threads)
        hashMB = try container.decode(Int.self, forKey: .hashMB)
        multiPV = try container.decode(Int.self, forKey: .multiPV)
        depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 30
    }
}

struct EngineConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var isDefault: Bool
    var source: Source
    var settings: EngineSettings

    enum Source: String, Codable {
        case downloaded
        case custom
        case cloud
    }

    init(id: UUID, name: String, path: String, isDefault: Bool, source: Source, settings: EngineSettings = .default) {
        self.id = id
        self.name = name
        self.path = path
        self.isDefault = isDefault
        self.source = source
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        source = try container.decode(Source.self, forKey: .source)
        settings = try container.decodeIfPresent(EngineSettings.self, forKey: .settings) ?? .default
    }
}
