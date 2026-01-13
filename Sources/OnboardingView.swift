import SwiftUI
import Foundation
import ApplicationServices
import AVFoundation
import AppKit

struct OnboardingStep {
    let title: String
    let description: String
    let imageName: String
    let buttonText: String
    let source: String?
    let action: ((@escaping (Double) -> Void) -> Void)?
    let skipCondition: (() -> Bool)?
    let progressBar: Bool

    init(
        title: String,
        description: String,
        imageName: String,
        buttonText: String,
        source: String? = nil,
        action: ((@escaping (Double) -> Void) -> Void)? = nil,
        skipCondition: (() -> Bool)? = nil,
        progressBar: Bool = false
    ) {
        self.title = title
        self.description = description
        self.imageName = imageName
        self.buttonText = buttonText
        self.source = source
        self.action = action
        self.skipCondition = skipCondition
        self.progressBar = progressBar
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var securityChecker = SecurityChecker.shared
    @State private var currentStepIndex = 0
    @State private var stepProgress: Double = 0
    @State private var progressTarget: Double = 0  // Target for smooth animation
    @State private var permissionRefreshTimer: Timer?
    @State private var compilationTimer: Timer?
    @State private var isCompiling: Bool = false

    private static func downloadProgressToStepProgress(downloadProgress: Double) -> Double {
        if downloadProgress > 0.8 {
            return 0.8
        } else if downloadProgress < 0.01 {
            return 0.01
        } else {
            return downloadProgress
        }
    }

    private func startCompilationAnimation() {
        isCompiling = true
        // Animate progress from 80% towards 99% over time to show activity during compilation
        compilationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if stepProgress >= 0.8 && stepProgress < 0.99 && isCompiling {
                    // Slow asymptotic approach to 99%
                    let remaining = 0.99 - stepProgress
                    stepProgress += remaining * 0.02
                }
            }
        }
    }
    
    private func startSmoothProgressAnimation() {
        isCompiling = true
        progressTarget = 0.65  // First target: animate towards 65% while download happens
        // Animate progress towards target milestone
        compilationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            DispatchQueue.main.async {
                if isCompiling && stepProgress < progressTarget {
                    // Smooth asymptotic approach to target
                    let remaining = progressTarget - stepProgress
                    stepProgress += remaining * 0.08
                }
            }
        }
    }
    
    private func updateProgressTarget(_ target: Double) {
        progressTarget = min(target, 0.99)
    }

    private func stopCompilationAnimation() {
        isCompiling = false
        compilationTimer?.invalidate()
        compilationTimer = nil
    }

    private var allSteps: [OnboardingStep] { [
        OnboardingStep(
            title: "Welcome to WhisperClip",
            description: "Let's set up the essential permissions and preferences so WhisperClip works smoothly.",
            imageName: "waveform.circle.fill",
            buttonText: "Next",
            skipCondition: nil
        ),
        OnboardingStep(
            title: "Move to Applications",
            description: """
            1. Click "Open Applications Folder"
            2. Drag WhisperClip into the Applications folder
            3. Launch the app from the Applications folder

            This ensures proper updates and reliable functionality.
            """,
            imageName: "folder.badge.plus",
            buttonText: "Open Applications Folder",
            action: { progress in
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["/Applications"]
                try? task.run()
            },
            skipCondition: {
                FileManager.default.fileExists(atPath: WhisperClipAppDir)
            }
        ),
        OnboardingStep(
            title: "Download Parakeet Model",
            description: """
            Required voice-to-text engine:
            • Optimized for Apple Neural Engine
            • Supports 25 European languages
            • Fast inference on Apple Silicon

            This is the default speech-to-text engine.
            """,
            imageName: "waveform.badge.plus",
            buttonText: "Download",
            source: "https://huggingface.co/\(ParakeetModelRepo)/\(ParakeetModelName)",
            action: { [self] progress in
                Task {
                    do {
                        // Start smooth animation immediately
                        await MainActor.run {
                            startSmoothProgressAnimation()
                        }
                        
                        try await ModelStorage.shared.downloadParakeetModels { downloadProgress in
                            Logger.log("Downloading Parakeet model: \(downloadProgress)", log: Logger.general)
                            Task { @MainActor in
                                // Update target based on milestones from download
                                // 0.70 -> target 0.85, 0.90 -> target 0.95
                                if downloadProgress >= 0.90 {
                                    updateProgressTarget(0.95)
                                } else if downloadProgress >= 0.70 {
                                    updateProgressTarget(0.85)
                                }
                            }
                        }
                        
                        await MainActor.run {
                            stopCompilationAnimation()
                            progress(1.0)
                        }
                    } catch {
                        Logger.log("Failed to download Parakeet model: \(error)", log: Logger.general, type: .error)
                        await MainActor.run {
                            stopCompilationAnimation()
                            stepProgress = 0  // Reset progress to allow retry or skip
                        }
                        do {
                            try ModelStorage.shared.deleteParakeetModels()
                        } catch {
                            Logger.log("Failed to delete Parakeet model: \(error)", log: Logger.general, type: .error)
                        }
                    }
                }
            },
            skipCondition: {
                ModelStorage.shared.parakeetModelsExist()
            },
            progressBar: true
        ),
        OnboardingStep(
            title: "Download WhisperKit Model (Optional)",
            description: """
            Optional alternative voice-to-text engine:
            • Supports 99 languages

            Click "Download" to download, or "Next" to use Parakeet instead.
            """,
            imageName: "mic.fill",
            buttonText: "Download",
            source: ModelStorage.shared.getModelFilesUrl(modelID: CurrentSTTModelRepo, subfolder: CurrentSTTModelName),
            action: { [self] progress in
                Task {
                    do {
                        let _ = try await ModelStorage.shared.downloadModel(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName, progress: { downloadProgress in
                            Logger.log("Downloading voice-to-text model: \(downloadProgress)", log: Logger.general)
                            progress(OnboardingView.downloadProgressToStepProgress(downloadProgress: downloadProgress))
                        })

                        await MainActor.run { startCompilationAnimation() }
                        try await ModelStorage.shared.preLoadModel(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName)
                        await MainActor.run { stopCompilationAnimation() }
                        await MainActor.run {
                            progress(1.0)
                        }
                    } catch {
                        Logger.log("Failed to download voice-to-text model: \(error)", log: Logger.general, type: .error)
                        await MainActor.run {
                            stopCompilationAnimation()
                            stepProgress = 0  // Reset progress to allow retry or skip
                        }
                        do {
                            try ModelStorage.shared.deleteModel(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName)
                        } catch {
                            Logger.log("Failed to delete voice-to-text model: \(error)", log: Logger.general, type: .error)
                        }
                    }
                }
            },
            skipCondition: {
                ModelStorage.shared.modelExists(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName) &&
                ModelStorage.shared.isModelLoaded(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName)
            },
            progressBar: true
        ),
        OnboardingStep(
            title: "Download LLM Model (Optional)",
            description: """
            Optional for:
            • Text-enhancing and prompts

            Click "Download" to download the model, or "Next" to download later from Settings.
            """,
            imageName: "brain.head.profile",
            buttonText: "Download",
            source: ModelStorage.shared.getModelFilesUrl(modelID: CurrentLLMModelRepo + "/" + CurrentLLMModelName, subfolder: ""),
            action: { [self] progress in
                Task {
                    let modelID = CurrentLLMModelRepo + "/" + CurrentLLMModelName
                    do {
                        let _ = try await ModelStorage.shared.downloadModel(modelRepo: modelID, modelName: "", progress: { downloadProgress in
                            Logger.log("Downloading LLM model: \(downloadProgress)", log: Logger.general)
                            progress(OnboardingView.downloadProgressToStepProgress(downloadProgress: downloadProgress))
                        })

                        await MainActor.run { startCompilationAnimation() }
                        try await ModelStorage.shared.preLoadModel(modelRepo: modelID, modelName: "")
                        await MainActor.run { stopCompilationAnimation() }
                        progress(1.0)
                    } catch {
                        Logger.log("Failed to download LLM model: \(error)", log: Logger.general, type: .error)
                        await MainActor.run {
                            stopCompilationAnimation()
                            stepProgress = 0  // Reset progress to allow retry or skip
                        }
                        do {
                            try ModelStorage.shared.deleteModel(modelRepo: modelID, modelName: "")
                        } catch {
                            Logger.log("Failed to delete LLM model: \(error)", log: Logger.general, type: .error)
                        }
                    }
                }
            },
            skipCondition: {
                ModelStorage.shared.modelExists(modelRepo: CurrentLLMModelRepo + "/" + CurrentLLMModelName, modelName: "") &&
                ModelStorage.shared.isModelLoaded(modelRepo: CurrentLLMModelRepo + "/" + CurrentLLMModelName, modelName: "")
            },
            progressBar: true
        ),
        OnboardingStep(
            title: "Accessibility Permission",
            description: """
            Required for:
            • Keyboard shortcuts

            Click "Request Access" to prompt for accessibility permission.
            """,
            imageName: "lock.shield.fill",
            buttonText: "Request Access",
            action: { progress in
                SecurityChecker.shared.requestAccessibilityPermission()
            },
            skipCondition: {
                SecurityChecker.shared.checkAccessibilityPermission().isGranted
            }
        ),
        OnboardingStep(
            title: "Microphone Access",
            description: """
            Required for:
            • Voice recording

            Click "Request Access" to prompt for microphone permission.
            """,
            imageName: "mic.fill",
            buttonText: "Request Access",
            action: { progress in
                SecurityChecker.shared.requestMicrophonePermission()
            },
            skipCondition: {
                SecurityChecker.shared.checkMicrophonePermission().isGranted
            }
        ),
        OnboardingStep(
            title: "Apple Events Permission",
            description: """
            Required for:
            • Auto-pasting text

            Click "Request Access" to prompt for Apple Events permission.
            """,
            imageName: "keyboard",
            buttonText: "Request Access",
            action: { progress in
                SecurityChecker.shared.requestAppleEventsPermission()
            },
            skipCondition: {
                SecurityChecker.shared.checkAppleEventsPermission().isGranted
            }
        ),
        OnboardingStep(
            title: "You're All Set!",
            description: """
            Quick Start:
            • Launch the app from the Applications folder
            • Press the hotkey (Option+Space by default) to start recording
            • Speak naturally
            • Press the hotkey again to stop
            • The text will be automatically pasted into the active app

            Access settings from the menu bar icon.
            """,
            imageName: "checkmark.circle.fill",
            buttonText: "Get Started",
            skipCondition: nil
        )
    ] }


    private func completeOnboarding() {
        // Set STT engine based on which models are downloaded
        // Priority: Parakeet (if downloaded) > WhisperKit (if downloaded) > default (Parakeet)
        if ModelStorage.shared.parakeetModelsExist() {
            settings.sttEngine = .parakeet
            Logger.log("Setting STT engine to Parakeet (model downloaded)", log: Logger.general)
        } else if ModelStorage.shared.modelExists(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName) &&
                  ModelStorage.shared.isModelLoaded(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName) {
            settings.sttEngine = .whisperKit
            Logger.log("Setting STT engine to WhisperKit (model downloaded)", log: Logger.general)
        }
        // Otherwise keep default (parakeet)
        
        settings.hasCompletedOnboarding = true

        if !GenericHelper.isDebug() && !GenericHelper.isLocalRun() {
            Logger.log("Relaunching app", log: Logger.general)
            do {
                try GenericHelper.launchApp(appPath: GenericHelper.getAppLocation())
                GenericHelper.terminateApp()
            } catch {
                Logger.log("Error launching app: \(error)", log: Logger.general, type: .error)
            }
        }
        
        stopPermissionRefreshTimer()
        dismiss()
    }
    
    private func startPermissionRefreshTimer() {
        // Stop any existing timer
        stopPermissionRefreshTimer()
        
        // Refresh permissions every 2 seconds during onboarding to catch state changes
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            SecurityChecker.shared.updateAllPermissions()
            
            // Reset stepProgress if current step is now completed (permission granted)
            if currentStepIndex < allSteps.count {
                let currentStep = allSteps[currentStepIndex]
                if stepProgress > 0.0 && stepProgress < 1.0 {
                    if let skipCondition = currentStep.skipCondition, skipCondition() {
                        // Permission is now granted, mark step as completed to enable Next button
                        stepProgress = 1.0
                    }
                }
            }
        }
    }
    
    private func stopPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
    }

    var body: some View {
        VStack(spacing: 30) {
            // Progress indicator
            HStack {
                ForEach(0..<allSteps.count, id: \.self) { index in
                    Circle()
                        .fill(currentStepIndex >= index ? Color.accentColor : Color.white.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            // Current step content
            VStack(spacing: 20) {
                if currentStepIndex >= 0 && currentStepIndex < allSteps.count {
                    let currentStep = allSteps[currentStepIndex]
                    Image(systemName: currentStep.imageName)
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)

                    Text(currentStep.title)
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)

                    VStack(alignment: .center, spacing: 8) {
                        // Main description
                        Text(currentStep.description)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 20)
                        
                        // Source URL section (only if source exists)
                        if let source = currentStep.source, !source.isEmpty {
                            VStack(spacing: 4) {
                                Text("Source:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    if let nsUrl = URL(string: source) {
                                        NSWorkspace.shared.open(nsUrl)
                                    }
                                }) {
                                    Text(source)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .underline()
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.center)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10)
                            }
                            .padding(.top, 4)
                        }
                    }


                    if let action = currentStep.action {
                        if !(currentStep.skipCondition?() ?? false) {
                            let progressCallback = { (progress: Double) in
                                Logger.log("Progress: \(progress)", log: Logger.general)
                                DispatchQueue.main.async {
                                    stepProgress = progress
                                }
                            }
                            if currentStep.progressBar {
                                VStack(spacing: 8) {
                                    ProgressView(value: stepProgress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 200)

                                    // Determine status text based on progress
                                    // Note: Parakeet doesn't have a compilation phase, so we use "Processing..." instead
                                    let isParakeetStep = currentStep.title.contains("Parakeet")
                                    let status = stepProgress < 0.8 
                                        ? "Downloading... \(Int(stepProgress * 100))%"
                                        : (isParakeetStep 
                                            ? "Processing... \(Int(stepProgress * 100))%"
                                            : "Compiling... \(Int(stepProgress * 100))%")
                                    Text(status)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            Button(currentStep.buttonText) {
                                stepProgress = 0.01
                                action(progressCallback)
                                
                                // Force an immediate refresh after requesting permission
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    SecurityChecker.shared.updateAllPermissions()
                                    
                                    // Set stepProgress to completed if permission was immediately granted
                                    if let skipCondition = currentStep.skipCondition, skipCondition() {
                                        stepProgress = 1.0
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 10)
                            .disabled(stepProgress > 0.0 && stepProgress < 1.0)
                        } else {
                            Text("Completed")
                                .foregroundColor(.green)
                                .padding(.top, 10)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            HStack {
                if currentStepIndex > 0 {
                    Button("Back") {
                        withAnimation {
                            if currentStepIndex > 0 {
                                stopCompilationAnimation()
                                currentStepIndex -= 1
                                stepProgress = 0
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(stepProgress > 0.0 && stepProgress < 1.0)
                }

                Spacer()

                if currentStepIndex >= 0 && currentStepIndex < allSteps.count - 1 {
                    Button("Next") {
                        withAnimation {
                            if currentStepIndex >= 0 && currentStepIndex < allSteps.count - 1 {
                                stopCompilationAnimation()
                                currentStepIndex += 1
                                stepProgress = 0
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(stepProgress > 0.0 && stepProgress < 1.0)
                } else {
                    Button("Get Started") {
                        stepProgress = 0
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(width: 600, height: 500)
        .background(Color.black)
        .onAppear {
            // Refresh permissions when view appears
            SecurityChecker.shared.updateAllPermissions()
            
            // Start a periodic refresh timer during onboarding
            startPermissionRefreshTimer()
        }
        .onDisappear {
            // Stop the refresh timer when onboarding is dismissed
            stopPermissionRefreshTimer()
            stopCompilationAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh permissions when app becomes active (user might have granted permission in System Settings)
            SecurityChecker.shared.updateAllPermissions()
        }
    }
}
