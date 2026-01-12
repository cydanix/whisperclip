let WhisperKitRepo = "argmaxinc/whisperkit-coreml"


let OpenAI_Whisper_Small_216MB = "openai_whisper-small_216MB"
let OpenAI_Whisper_Large_V3_V20240930_Turbo_632MB = "openai_whisper-large-v3-v20240930_turbo_632MB"
let OpenAI_Whisper_Large_V2_Turbo_955MB = "openai_whisper-large-v2_turbo_955MB"
let Distil_Whisper_Large_V3_Turbo_600MB = "distil-whisper_distil-large-v3_turbo_600MB"
let OpenAI_Whisper_Large_V3_V20240930 = "openai_whisper-large-v3-v20240930"

let WhisperKitModelNames = [
    OpenAI_Whisper_Small_216MB,
    OpenAI_Whisper_Large_V3_V20240930_Turbo_632MB,
    Distil_Whisper_Large_V3_Turbo_600MB,
    OpenAI_Whisper_Large_V2_Turbo_955MB,
    OpenAI_Whisper_Large_V3_V20240930,
]

let MlxCommunityRepo = "mlx-community"

let Gemma_2_9b_it_4bit = "gemma-2-9b-it-4bit"
let Meta_Llama_3_8B_Instruct_4bit = "Meta-Llama-3-8B-Instruct-4bit"
let DeepSeek_R1_Distill_Qwen_7B_4bit = "DeepSeek-R1-Distill-Qwen-7B-4bit"
let Mistral_7B_Instruct_v0_3_4bit = "Mistral-7B-Instruct-v0.3-4bit"
let Qwen_3_8B_4bit = "Qwen-3-8B-4bit"
let Phi_3_5_mini_instruct_4bit = "Phi-3.5-mini-instruct-4bit"
let Gemma_2_2b_it_4bit = "gemma-2-2b-it-4bit"
let Qwen2_5_1_5B_Instruct_4bit = "Qwen2.5-1.5B-Instruct-4bit"
let Llama_3_2_3B_Instruct_4bit = "Llama-3.2-3B-Instruct-4bit"
let Qwen3_4B_4bit = "Qwen3-4B-4bit"

let TextLLMModelNames = [
    Gemma_2_9b_it_4bit,
    Meta_Llama_3_8B_Instruct_4bit,
    DeepSeek_R1_Distill_Qwen_7B_4bit,
    Mistral_7B_Instruct_v0_3_4bit,
    Qwen_3_8B_4bit,
    Phi_3_5_mini_instruct_4bit,
    Gemma_2_2b_it_4bit,
    Qwen2_5_1_5B_Instruct_4bit,
]

let WhisperClipAppDir = "/Applications/WhisperClip.app"

let WhisperClipSite = "https://whisperclip.com"
let WhisperClipCompanyName = "Cydanix LLC"
let WhisperClipDonateLink = "https://donate.stripe.com/14A3cvayk1vbfys8iUaIM22"

let WhisperClipAppName = "WhisperClip"

let KiloByte = Int64(1024)
let MegaByte = KiloByte * KiloByte
let GigaByte = MegaByte * KiloByte
let MinimalFreeDiskSpace = GigaByte * Int64(20)

let RecordingAutoStopIntervalSeconds = 10 * 60

let CurrentSTTModelRepo = WhisperKitRepo;
let CurrentSTTModelName = OpenAI_Whisper_Large_V3_V20240930_Turbo_632MB;

let CurrentLLMModelRepo = MlxCommunityRepo;
let CurrentLLMModelName = Qwen3_4B_4bit;

// Parakeet model constants
let ParakeetModelRepo = "FluidInference"
let ParakeetModelName = "parakeet-tdt-0.6b-v3-coreml"

// Speech-to-Text Engine options
enum STTEngine: String, CaseIterable {
    case whisperKit = "whisperKit"
    case parakeet = "parakeet"

    var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet: return "Parakeet"
        }
    }
}