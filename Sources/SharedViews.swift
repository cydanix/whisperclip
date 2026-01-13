import SwiftUI

struct ResultView: View {
    let resultText: String
    let statusMessage: String
    @Binding var showShareSheet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result")
                    .font(.headline)
                    .foregroundColor(.white)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Spacer()

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(resultText.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(resultText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                        .foregroundColor(.white)
                        .id("resultTextBottom")
                }
                .frame(height: 150)
                .onChange(of: resultText) {
                    withAnimation {
                        proxy.scrollTo("resultTextBottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding(.top, 16)
        .sheet(isPresented: $showShareSheet) {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showShareSheet = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .padding([.top, .trailing], 10)
                }

                if #available(macOS 13.0, *) {
                    ShareLink("Share", item: resultText)
                        .padding()
                } else {
                    Text("Sharing not available on this OS version")
                        .padding()
                }
            }
        }
    }
}

struct ErrorView: View {
    let errorMessage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error")
                .font(.headline)
                .foregroundColor(.red)

            ScrollView {
                Text(errorMessage)
                    .font(.body)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
            .frame(height: 100)
        }
        .padding(.top, 16)
    }
}
