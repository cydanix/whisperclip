import Foundation

struct TranscriptionItem: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let source: TranscriptionSource
    let timestamp: Date
    let filename: String?  // For file-based transcriptions
    
    init(text: String, source: TranscriptionSource, filename: String? = nil) {
        self.id = UUID()
        self.text = text
        self.source = source
        self.timestamp = Date()
        self.filename = filename
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TranscriptionItem, rhs: TranscriptionItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum TranscriptionSource: String, Codable {
    case microphone
    case file
}

@MainActor
class TranscriptionHistory: ObservableObject {
    static let shared = TranscriptionHistory()
    
    private let maxItems = 100
    private let storageKey = "transcriptionHistory"
    
    @Published private(set) var items: [TranscriptionItem] = []
    
    private init() {
        loadHistory()
    }
    
    func add(text: String, source: TranscriptionSource, filename: String? = nil) {
        let item = TranscriptionItem(text: text, source: source, filename: filename)
        items.insert(item, at: 0)
        
        // Keep only the most recent items
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveHistory()
    }
    
    func remove(item: TranscriptionItem) {
        items.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    func clearAll() {
        items.removeAll()
        saveHistory()
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            items = try JSONDecoder().decode([TranscriptionItem].self, from: data)
        } catch {
            Logger.log("Failed to load transcription history: \(error)", log: Logger.general, type: .error)
        }
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Logger.log("Failed to save transcription history: \(error)", log: Logger.general, type: .error)
        }
    }
}
