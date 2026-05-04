const ttsPreviewSample =
    "Oh, hello there! I've been waiting for you to test me. I sound pretty good!";

const ttsMinRamBytes = 4 * 1024 * 1024 * 1024;

const ttsParentSubdir = 'tts';
const kittenModelSubdir = 'tts/kitten';
const kokoroModelSubdir = 'tts/kokoro';
const supertonicModelSubdir = 'tts/supertonic';

const ttsDictUrl = 'https://huggingface.co/datasets/palshub/phonemizer-dicts/resolve/main/en-us.bin';

const kittenModelBaseUrl =
    'https://huggingface.co/palshub/kitten-tts-nano-0.8-fp32/resolve/main';

const kokoroModelBaseUrl =
    'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main';
const kokoroVoicesBaseUrl = '$kokoroModelBaseUrl/voices';

const supertonicModelBaseUrl =
    'https://huggingface.co/Supertone/supertonic-2/resolve/main';
const supertonicVoicesBaseUrl = '$supertonicModelBaseUrl/voice_styles';

// NOTE: palshub/tts-manifests is a private HuggingFace repo (returns 401).
// The Tokenizer already includes a full fallback vocab, so this file is not
// required. The URL is kept here for reference only.
// const voicesManifestUrl = 'https://huggingface.co/palshub/tts-manifests/resolve/main/voices-manifest.json';

const maxChunkSize = 200;
const streamTargetChars = 300;
const supertonicStepsDefault = 3;
const supertonicStepsOptions = [1, 2, 3, 5, 10, 20];

const maxRetries = 3;
const retryDelayMs = 150;
