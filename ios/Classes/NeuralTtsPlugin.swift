import Flutter
import UIKit

public class SwiftNeuralTtsPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.localmind.neural_tts",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftNeuralTtsPlugin()
        instance.methodChannel = channel
        registrar.addMethodCallHandler(instance.handle)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "tts.initialize":
                result(nil)
            case "tts.speak":
                result(nil)
            case "tts.stream.append":
                result(nil)
            case "tts.stream.finalize":
                result(nil)
            case "tts.stream.cancel":
                result(nil)
            case "tts.stop":
                result(nil)
            case "tts.release":
                result(nil)
            case "tts.getAvailableVoices":
                result([])
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let err {
            result(FlutterError(code: "TTS_ERROR", message: err.localizedDescription, details: nil))
        }
    }
}
