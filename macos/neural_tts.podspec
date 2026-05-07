Pod::Spec.new do |s|
  s.name             = 'neural_tts'
  s.version          = '0.1.0'
  s.summary          = 'On-device neural TTS engine for Flutter.'
  s.description      = 'Supports Kitten, Kokoro, Supertonic, and System OS TTS via native ONNX Runtime.'
  s.homepage         = 'https://github.com/localmind/neural_tts'
  s.license          = { :type => 'MIT' }
  s.author           = { 'LocalMind' => 'dev@localmind.ai' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
