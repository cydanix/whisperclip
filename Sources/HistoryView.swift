import SwiftUI

struct HistoryView: View {
    @ObservedObject private var history = TranscriptionHistory.shared
    @State private var selectedItem: TranscriptionItem?
    @State private var showingClearConfirmation = false
    @State private var searchText: String = ""
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private var filteredItems: [TranscriptionItem] {
        if searchText.isEmpty {
            return history.items
        }
        return history.items.filter { item in
            item.text.localizedCaseInsensitiveContains(searchText) ||
            (item.filename?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.1),
                    Color(red: 0.04, green: 0.04, blue: 0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if history.items.isEmpty {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .stroke(Color.purple.opacity(0.2), lineWidth: 2)
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 50, weight: .light))
                            .foregroundColor(.purple.opacity(0.6))
                    }
                    
                    VStack(spacing: 8) {
                        Text("No transcriptions yet")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Your transcription history will appear here")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("History")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("\(history.items.count) transcription\(history.items.count == 1 ? "" : "s")")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button {
                            showingClearConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("Clear")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        TextField("Search transcriptions...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // History list
                    if filteredItems.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("No results found")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray)
                            Text("Try a different search term")
                                .font(.system(size: 13))
                                .foregroundColor(.gray.opacity(0.7))
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredItems) { item in
                                    HistoryItemRow(item: item, dateFormatter: dateFormatter, searchText: searchText)
                                        .contextMenu {
                                            Button {
                                                GenericHelper.copyToClipboard(text: item.text)
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                            
                                            Divider()
                                            
                                            Button(role: .destructive) {
                                                history.remove(item: item)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
        .foregroundColor(.white)
        .alert("Clear History", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                history.clearAll()
            }
        } message: {
            Text("Are you sure you want to clear all transcription history? This action cannot be undone.")
        }
    }
}

struct HistoryItemRow: View {
    let item: TranscriptionItem
    let dateFormatter: DateFormatter
    var searchText: String = ""
    @State private var isCopied = false
    @State private var isHovered = false
    
    private var sourceColor: Color {
        item.source == .microphone ? .red : .blue
    }
    
    private func highlightedText(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        guard !searchText.isEmpty else {
            return attributedString
        }
        
        let lowercasedText = text.lowercased()
        let lowercasedSearch = searchText.lowercased()
        
        var searchStartIndex = lowercasedText.startIndex
        while let range = lowercasedText.range(of: lowercasedSearch, range: searchStartIndex..<lowercasedText.endIndex) {
            let attrRange = AttributedString.Index(range.lowerBound, within: attributedString)!..<AttributedString.Index(range.upperBound, within: attributedString)!
            attributedString[attrRange].backgroundColor = .yellow.opacity(0.3)
            attributedString[attrRange].foregroundColor = .yellow
            searchStartIndex = range.upperBound
        }
        
        return attributedString
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                // Source icon
                ZStack {
                    Circle()
                        .fill(sourceColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: item.source == .microphone ? "mic.fill" : "doc.fill")
                        .foregroundColor(sourceColor)
                        .font(.system(size: 14))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    if let filename = item.filename {
                        Text(filename)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    } else {
                        Text(item.source == .microphone ? "Voice Recording" : "Audio File")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Text(dateFormatter.string(from: item.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Copy button
                Button {
                    GenericHelper.copyToClipboard(text: item.text)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "Copied!" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isCopied ? .green : .white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(isCopied ? 0.15 : 0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            // Text content
            Text(highlightedText(item.text))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
