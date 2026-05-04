#import "NeuralTtsPlugin.h"
#import <neural_tts/neural_tts-Swift.h>

@implementation NeuralTtsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    [SwiftNeuralTtsPlugin registerWithRegistrar:registrar];
}
@end
