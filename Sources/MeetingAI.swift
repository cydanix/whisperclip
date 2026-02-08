import Foundation

/// AI-powered meeting analysis using embedded LLM
class MeetingAI {
    static let shared = MeetingAI()
    
    private let llm = LLM.shared
    
    private init() {}
    
    // MARK: - Summary Generation
    
    /// Generate a complete meeting summary from transcript
    func generateSummary(from meeting: MeetingNote) async throws -> MeetingSummary {
        // Check if LLM is ready
        let isReady = try await llm.isReady()
        guard isReady else {
            throw MeetingAIError.llmNotReady
        }
        
        let transcript = meeting.fullTranscript
        guard !transcript.isEmpty else {
            throw MeetingAIError.emptyTranscript
        }
        
        var summary = MeetingSummary()
        summary.generatedAt = Date()
        
        // Generate brief summary
        summary.brief = try await generateBriefSummary(transcript: transcript)
        
        // Generate detailed summary
        summary.detailed = try await generateDetailedSummary(transcript: transcript)
        
        // Extract action items
        summary.actionItems = try await extractActionItems(transcript: transcript)
        
        // Extract key decisions
        summary.decisions = try await extractDecisions(transcript: transcript)
        
        // Generate follow-ups
        summary.followUps = try await extractFollowUps(transcript: transcript)
        
        // Extract topics
        summary.topics = try await extractTopics(transcript: transcript)
        
        return summary
    }
    
    // MARK: - Individual Generation Methods
    
    private func generateBriefSummary(transcript: String) async throws -> String {
        let systemPrompt = """
        You are a meeting assistant. Provide a 1-2 sentence summary of the meeting that captures the main purpose and outcome.
        Be concise and focus on the most important point. Do not include any preamble or explanation.
        """
        
        let userPrompt = """
        Meeting Transcript:
        \(truncateForLLM(transcript, maxChars: 24000))
        
        Brief Summary:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return cleanResponse(result)
    }
    
    private func generateDetailedSummary(transcript: String) async throws -> String {
        let systemPrompt = """
        You are a meeting assistant. Provide a comprehensive summary of the meeting in 3-5 paragraphs.
        Include the main topics discussed, key points made by participants, and any conclusions reached.
        Do not include any preamble or explanation, just the summary.
        """
        
        let userPrompt = """
        Meeting Transcript:
        \(truncateForLLM(transcript, maxChars: 24000))
        
        Detailed Summary:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return cleanResponse(result)
    }
    
    private func extractActionItems(transcript: String) async throws -> [ActionItem] {
        let systemPrompt = """
        You are a meeting assistant. Extract action items from the meeting transcript.
        List each action item on a new line, starting with "- ".
        Include the assignee in parentheses if mentioned. Example: "- Complete the report (John)"
        Only output action items, nothing else. If there are no action items, output "NONE".
        """
        
        let userPrompt = """
        Meeting Transcript:
        \(truncateForLLM(transcript, maxChars: 24000))
        
        Action Items:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return parseActionItems(result)
    }
    
    private func extractDecisions(transcript: String) async throws -> [String] {
        let systemPrompt = """
        You are a meeting assistant. Extract key decisions made during the meeting.
        List each decision on a new line, starting with "- ".
        Only output decisions, nothing else. If there are no clear decisions, output "NONE".
        """
        
        let userPrompt = """
        Meeting Transcript:
        \(truncateForLLM(transcript, maxChars: 24000))
        
        Decisions:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return parseListItems(result)
    }
    
    private func extractFollowUps(transcript: String) async throws -> [String] {
        let systemPrompt = """
        You are a meeting assistant. Identify items that need follow-up after this meeting.
        List each follow-up item on a new line, starting with "- ".
        Only output follow-up items, nothing else. If there are none, output "NONE".
        """
        
        let userPrompt = """
        Meeting Transcript:
        \(truncateForLLM(transcript, maxChars: 24000))
        
        Follow-ups:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return parseListItems(result)
    }
    
    private func extractTopics(transcript: String) async throws -> [MeetingTopic] {
        let systemPrompt = """
        You are a meeting assistant. Identify the main topics discussed in the meeting.
        For each topic, provide:
        TOPIC: [topic title]
        SUMMARY: [1-2 sentence summary of the discussion on this topic]
        
        List up to 5 main topics. Do not include any preamble.
        """
        
        let userPrompt = """
        Meeting Transcript:
        \(truncateForLLM(transcript, maxChars: 24000))
        
        Topics:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return parseTopics(result)
    }
    
    // MARK: - Q&A
    
    /// Answer a question about the meeting
    func askQuestion(question: String, meeting: MeetingNote) async throws -> String {
        let isReady = try await llm.isReady()
        guard isReady else {
            throw MeetingAIError.llmNotReady
        }
        
        let transcript = meeting.fullTranscript
        guard !transcript.isEmpty else {
            throw MeetingAIError.emptyTranscript
        }
        
        let systemPrompt = """
        You are a helpful meeting assistant. Answer questions about the meeting based on the transcript provided.
        Be accurate and only reference information that appears in the transcript.
        If the question cannot be answered from the transcript, say so clearly.
        Keep answers concise but informative.
        """
        
        let contextInfo = """
        Meeting: \(meeting.title)
        Date: \(formatDate(meeting.startedAt))
        Duration: \(meeting.formattedDuration)
        """
        
        var userPrompt = """
        Meeting Information:
        \(contextInfo)
        
        Transcript:
        \(truncateForLLM(transcript, maxChars: 20000))
        
        """
        
        // Include existing summary if available
        if !meeting.summary.brief.isEmpty {
            userPrompt += """
            
            Summary:
            \(meeting.summary.brief)
            
            """
        }
        
        userPrompt += """
        
        Question: \(question)
        
        Answer:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return cleanResponse(result)
    }
    
    // MARK: - Enhance Transcript
    
    /// Clean up and enhance a transcript segment
    func enhanceSegment(segment: MeetingSegment) async throws -> String {
        let isReady = try await llm.isReady()
        guard isReady else {
            throw MeetingAIError.llmNotReady
        }
        
        let systemPrompt = """
        You are a transcription assistant. Clean up the following speech-to-text output:
        - Fix obvious transcription errors
        - Add proper punctuation
        - Remove filler words (um, uh, like)
        - Maintain the original meaning
        Only output the cleaned text, nothing else.
        """
        
        let userPrompt = """
        Original: \(segment.text)
        
        Cleaned:
        """
        
        let result = try await llm.execute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return cleanResponse(result)
    }
    
    // MARK: - Parsing Helpers
    
    private func parseActionItems(_ text: String) -> [ActionItem] {
        let cleaned = cleanResponse(text)
        
        if cleaned.uppercased().contains("NONE") {
            return []
        }
        
        var items: [ActionItem] = []
        let lines = cleaned.components(separatedBy: .newlines)
        
        for line in lines {
            var cleanedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Remove bullet points
            if cleanedLine.hasPrefix("-") || cleanedLine.hasPrefix("•") || cleanedLine.hasPrefix("*") {
                cleanedLine = String(cleanedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            
            // Skip empty lines
            guard !cleanedLine.isEmpty else { continue }
            
            // Extract assignee if present
            var assignee: String?
            if let parenRange = cleanedLine.range(of: "\\([^)]+\\)", options: .regularExpression) {
                let assigneeText = String(cleanedLine[parenRange])
                assignee = assigneeText.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                cleanedLine = cleanedLine.replacingCharacters(in: parenRange, with: "").trimmingCharacters(in: .whitespaces)
            }
            
            if !cleanedLine.isEmpty {
                items.append(ActionItem(text: cleanedLine, assignee: assignee))
            }
        }
        
        return items
    }
    
    private func parseListItems(_ text: String) -> [String] {
        let cleaned = cleanResponse(text)
        
        if cleaned.uppercased().contains("NONE") {
            return []
        }
        
        var items: [String] = []
        let lines = cleaned.components(separatedBy: .newlines)
        
        for line in lines {
            var cleanedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Remove bullet points
            if cleanedLine.hasPrefix("-") || cleanedLine.hasPrefix("•") || cleanedLine.hasPrefix("*") {
                cleanedLine = String(cleanedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            
            // Remove numbering
            if let dotRange = cleanedLine.range(of: "^\\d+\\.\\s*", options: .regularExpression) {
                cleanedLine = String(cleanedLine[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            
            if !cleanedLine.isEmpty {
                items.append(cleanedLine)
            }
        }
        
        return items
    }
    
    private func parseTopics(_ text: String) -> [MeetingTopic] {
        let cleaned = cleanResponse(text)
        var topics: [MeetingTopic] = []
        
        // Split by TOPIC: markers
        let topicBlocks = cleaned.components(separatedBy: "TOPIC:")
        
        for block in topicBlocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            var title = ""
            var summary = ""
            
            // Extract title and summary
            if let summaryRange = trimmed.range(of: "SUMMARY:", options: .caseInsensitive) {
                title = String(trimmed[..<summaryRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                summary = String(trimmed[summaryRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // Just use the whole block as title if no SUMMARY marker
                let lines = trimmed.components(separatedBy: .newlines)
                if let firstLine = lines.first {
                    title = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if lines.count > 1 {
                        summary = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            
            if !title.isEmpty {
                topics.append(MeetingTopic(title: title, summary: summary))
            }
        }
        
        return topics
    }
    
    // MARK: - Utility Methods
    
    private func truncateForLLM(_ text: String, maxChars: Int) -> String {
        if text.count <= maxChars {
            return text
        }
        
        // Try to truncate at a sentence boundary
        let truncated = String(text.prefix(maxChars))
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }
        
        return truncated + "..."
    }
    
    private func cleanResponse(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common LLM artifacts
        let artifactsToRemove = [
            "Here's", "Here is", "Sure!", "Of course!", "Certainly!",
            "Based on the transcript", "According to the meeting",
            "```", "---", "===",
        ]
        
        for artifact in artifactsToRemove {
            if cleaned.lowercased().hasPrefix(artifact.lowercased()) {
                cleaned = String(cleaned.dropFirst(artifact.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Also remove any following colon or newline
                if cleaned.hasPrefix(":") || cleaned.hasPrefix("\n") {
                    cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return cleaned
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Readiness Check
    
    func isReady() async -> Bool {
        do {
            return try await llm.isReady()
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum MeetingAIError: LocalizedError {
    case llmNotReady
    case emptyTranscript
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .llmNotReady:
            return "AI model is not ready. Please download it from the Setup Guide."
        case .emptyTranscript:
            return "Meeting has no transcript to analyze."
        case .generationFailed(let message):
            return "Failed to generate: \(message)"
        }
    }
}
