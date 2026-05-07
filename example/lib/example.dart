import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neural_tts/neural_tts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neural TTS Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TTSExampleScreen(),
    );
  }
}

class TTSExampleScreen extends StatefulWidget {
  const TTSExampleScreen({super.key});

  @override
  State<TTSExampleScreen> createState() => _TTSExampleScreenState();
}

class _TTSExampleScreenState extends State<TTSExampleScreen> {
  final ModelDownloader _downloader = ModelDownloader();
  final TextEditingController _textController = TextEditingController(
    text:
        'Hello! This is a test of the neural text to speech engine. It sounds much more natural than traditional systems.',
  );
  final Phonemizer _phonemizer = Phonemizer();

  EngineId _selectedEngineId = EngineId.kitten;
  Engine? _currentEngine;
  List<Voice> _voices = [];
  Voice? _selectedVoice;
  EngineStatus _status = const EngineStatus(state: EngineState.notInstalled);
  bool _isLoading = false;
  double _downloadProgress = 0;
  String _downloadStatus = '';
  String? _lastError;
  bool _usePhonemizer = true;
  bool _useEspeak = true;
  String _selectedLanguage = 'en-US';
  String _phonemizedText = '';
  Phonemizer? _espeakPhonemizer;

  final List<String> _languages = ['en-US', 'en-GB', 'zh', 'ja', 'ko'];

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _updatePhonemes();
    _textController.addListener(_updatePhonemes);
  }

  @override
  void dispose() {
    _textController.removeListener(_updatePhonemes);
    _textController.dispose();
    super.dispose();
  }

  void _updatePhonemes() {
    if (!_usePhonemizer) {
      if (_phonemizedText.isNotEmpty) {
        setState(() => _phonemizedText = '');
      }
      return;
    }

    final text = _textController.text;
    if (text.isEmpty) {
      if (_phonemizedText.isNotEmpty) {
        setState(() => _phonemizedText = '');
      }
      return;
    }

    try {
      final phonemizer = (_useEspeak && _espeakPhonemizer != null)
          ? _espeakPhonemizer!
          : _phonemizer;
      final phonemes = phonemizer.convert(
        text,
        language: _selectedLanguage.toLowerCase(),
      );
      setState(() => _phonemizedText = phonemes);
    } catch (e) {
      debugPrint('Phonemization error: $e');
    }
  }

  Future<void> _checkStatus() async {
    final engine = createEngine(_selectedEngineId);
    final status = await engine.checkStatus();
    setState(() {
      _currentEngine = engine;
      _status = status;
    });

    if (status.isInstalled) {
      final voices = await engine.getVoices();

      // Initialize espeak if data is present
      if (await _downloader.isEngineDownloaded(_selectedEngineId)) {
        final ttsDir = await _downloader.getTtsDir();
        if (_espeakPhonemizer == null) {
          try {
            _espeakPhonemizer = EspeakPhonemizer(
              dataPath: ttsDir.path,
              language: _selectedLanguage.toLowerCase(),
            );
          } catch (e) {
            debugPrint('Failed to init EspeakPhonemizer: $e');
          }
        }
      }

      setState(() {
        _voices = voices;
        if (voices.isNotEmpty) {
          _selectedVoice = voices.first;
        }
      });
    }
  }

  Future<void> _downloadEngine() async {
    setState(() {
      _isLoading = true;
      _downloadProgress = 0;
      _downloadStatus = 'Starting download...';
      _lastError = null;
    });

    try {
      final stream = _downloader.downloadEngineFiles(_selectedEngineId);
      await for (final progress in stream) {
        setState(() {
          _downloadProgress = progress.receivedBytes / progress.totalBytes;
          _downloadStatus =
              'Downloading ${progress.fileName}: ${(progress.receivedBytes / 1024 / 1024).toStringAsFixed(1)} MB / ${(progress.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB';
        });
      }
      await _checkStatus();
    } catch (e, st) {
      debugPrint('[Example] Download error: $e');
      debugPrint('[Example] Stack trace: $st');
      if (!mounted) return;
      setState(() {
        _lastError = '$e\n\nStack trace:\n$st';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _play() async {
    if (_selectedVoice == null || _currentEngine == null) return;

    setState(() => _isLoading = true);
    try {
      if (_useEspeak && _espeakPhonemizer != null) {
        _currentEngine!.setPhonemizer(_espeakPhonemizer!);
      } else {
        _currentEngine!.setPhonemizer(_phonemizer);
      }

      await _currentEngine!.play(
        _textController.text,
        _selectedVoice!,
        language: _selectedLanguage,
        phonemize: _usePhonemizer,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playback failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neural TTS Example'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkStatus),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Engine Selection',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<EngineId>(
                        isExpanded: true,
                        value: _selectedEngineId,
                        onChanged: (id) {
                          if (id != null) {
                            setState(() => _selectedEngineId = id);
                            _checkStatus();
                          }
                        },
                        items: EngineId.values.map((id) {
                          return DropdownMenuItem(
                            value: id,
                            child: Text(EngineMeta.forEngine(id).name),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      const Text('Language'),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedLanguage,
                        onChanged: (lang) {
                          if (lang != null) {
                            setState(() => _selectedLanguage = lang);
                            _updatePhonemes();
                          }
                        },
                        items: _languages.map((lang) {
                          return DropdownMenuItem(
                            value: lang,
                            child: Text(lang),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Text('Status: ${_status.state.name}'),
                      if (_status.error != null)
                        Text(
                          'Error: ${_status.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_status.isNotInstalled)
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _downloadEngine,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Engine Models'),
                )
              else if (_status.isInstalled)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Voice Selection',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<Voice>(
                          isExpanded: true,
                          value: _selectedVoice,
                          onChanged: (voice) {
                            setState(() => _selectedVoice = voice);
                          },
                          items: _voices.map((voice) {
                            return DropdownMenuItem<Voice>(
                              value: voice,
                              child: Text(
                                '${voice.name} (${voice.language ?? 'en'})',
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Use Espeak-NG (Recommended)'),
                      subtitle: const Text('High-fidelity IPA phonemization'),
                      value: _useEspeak && _usePhonemizer,
                      onChanged: (value) {
                        setState(() {
                          _usePhonemizer = value;
                          if (value) _useEspeak = true;
                        });
                        _updatePhonemes();
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Use Rule-based (Legacy)'),
                      subtitle: const Text('Lightweight but less accurate'),
                      value: !_useEspeak && _usePhonemizer,
                      onChanged: (value) {
                        setState(() {
                          _usePhonemizer = value;
                          if (value) _useEspeak = false;
                        });
                        _updatePhonemes();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _textController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Text to Speak',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_phonemizedText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    border: Border.all(color: Colors.deepPurple.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.translate,
                            size: 16,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Phonemes (IPA)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: _phonemizedText),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Phonemes copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.copy,
                                    size: 14,
                                    color: Colors.deepPurple,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _phonemizedText,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_isLoading)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: _downloadProgress > 0 && _downloadProgress <= 1
                          ? _downloadProgress
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(_downloadStatus),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _status.isInstalled ? _play : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Speak Text'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _currentEngine?.stop(),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
              if (_lastError != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Download Error',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _lastError = null),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _lastError!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
