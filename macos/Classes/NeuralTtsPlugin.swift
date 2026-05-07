import FlutterMacOS
import Foundation

public class NeuralTtsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.localmind.neural_tts", binaryMessenger: registrar.messenger)
    let instance = NeuralTtsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "tts.initialize":
      // Supertonic is now handled in Dart. 
      // For other engines, we might return not implemented or implement them here later.
      result(nil)
    case "tts.speak":
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
  }
}
