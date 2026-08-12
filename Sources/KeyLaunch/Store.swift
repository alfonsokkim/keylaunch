import Cocoa

/// What physically arrived from the keyboard.
///
/// The Mac "media row" keys are not plain virtual keycodes. Mission Control,
/// Spotlight and Dictation arrive as NSSystemDefined (type 14, subtype 8)
/// events carrying their own code space, while ordinary keys arrive as
/// .keyDown. We record whichever one the user actually pressed rather than
/// hardcoding a guess, because the codes differ between keyboard models.
enum Trigger: Codable, Equatable {
    case system(Int)
    case key(Int)

    var label: String {
        switch self {
        case .system(let code):
            return Trigger.systemNames[code] ?? "Media key \(code)"
        case .key(let code):
            return Trigger.keyNames[code] ?? "Key \(code)"
        }
    }

    private static let systemNames: [Int: String] = [
        0: "Volume Up", 1: "Volume Down", 2: "Brightness Up", 3: "Brightness Down",
        7: "Mute", 13: "Launchpad", 14: "Eject", 16: "Play/Pause", 17: "Next",
        18: "Previous", 21: "Keyboard Light Up", 22: "Keyboard Light Down",
        // Codes seen on the modern Magic Keyboard function row.
        // Confirmed empirically by learn mode; names are best effort.
        160: "Mission Control", 176: "Spotlight", 177: "Dictation",
    ]

    private static let keyNames: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]
}

struct Mapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: Trigger?
    /// Stored as a path so the config file stays readable and editable.
    var appPath: String?

    var appURL: URL? { appPath.map { URL(fileURLWithPath: $0) } }
    var appName: String? {
        guard let p = appPath else { return nil }
        return (p as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
    var isComplete: Bool { trigger != nil && appPath != nil }
}

final class Store: ObservableObject {
    static let shared = Store()

    @Published var mappings: [Mapping] = [] { didSet { save() } }
    /// Index of the row currently waiting to capture a keypress, if any.
    @Published var learningID: UUID?
    /// Set briefly when a mapping fires, so the settings window can show it worked.
    @Published var lastFired: String?

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyLaunch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    private var loading = false

    private init() {
        loading = true
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Mapping].self, from: data) {
            mappings = decoded
        }
        if mappings.isEmpty {
            mappings = [Mapping(), Mapping(), Mapping()]
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(mappings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func mapping(for trigger: Trigger) -> Mapping? {
        mappings.first { $0.trigger == trigger && $0.appPath != nil }
    }

    func setTrigger(_ trigger: Trigger, for id: UUID) {
        // A trigger can only drive one app, so clear it from any other row.
        for i in mappings.indices where mappings[i].trigger == trigger && mappings[i].id != id {
            mappings[i].trigger = nil
        }
        if let i = mappings.firstIndex(where: { $0.id == id }) {
            mappings[i].trigger = trigger
        }
    }

    func setApp(_ url: URL, for id: UUID) {
        if let i = mappings.firstIndex(where: { $0.id == id }) {
            mappings[i].appPath = url.path
        }
    }

    func clear(_ id: UUID) {
        if let i = mappings.firstIndex(where: { $0.id == id }) {
            mappings[i].trigger = nil
            mappings[i].appPath = nil
        }
    }
}
