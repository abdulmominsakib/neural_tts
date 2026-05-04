import 'package:flutter/material.dart';
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

  EngineId _selectedEngineId = EngineId.kitten;
  Engine? _currentEngine;
  List<Voice> _voices = [];
  Voice? _selectedVoice;
  EngineStatus _status = const EngineStatus(state: EngineState.notInstalled);
  bool _isLoading = false;
  double _downloadProgress = 0;
  String _downloadStatus = '';
  String? _lastError;  // persists error across rebuilds

  @override
  void initState() {
    super.initState();
    _checkStatus();
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
      await _currentEngine!.play(_textController.text, _selectedVoice!);
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
      body: SingleChildScrollView(
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
            TextField(
              controller: _textController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Text to Speak',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              Column(
                children: [
                  LinearProgressIndicator(value: _downloadProgress > 0 && _downloadProgress <= 1 ? _downloadProgress : null),
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
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        const Text('Download Error', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
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
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
