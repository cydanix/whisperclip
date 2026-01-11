import SwiftUI
import AppKit

struct DonationDialog: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundColor(.pink)
            
            Text("Thank you for choosing WhisperClip!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Enjoying WhisperClip? A small contribution helps us keep improving this privacy-first, open source app — no subscriptions, no data collection, just great voice-to-text.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            HStack(spacing: 16) {
                Button("Maybe Later") {
                    SettingsStore.shared.donationDialogShown = true
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Donate ❤️") {
                    SettingsStore.shared.donationDialogShown = true
                    openDonateLink()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 420, height: 320)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
    
    private func openDonateLink() {
        if let url = URL(string: WhisperClipDonateLink) {
            NSWorkspace.shared.open(url)
        }
    }
}

// Helper function to open donate link from anywhere
func openDonateLink() {
    if let url = URL(string: WhisperClipDonateLink) {
        NSWorkspace.shared.open(url)
    }
}
