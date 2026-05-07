import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';

/// Helper script to compile espeak-ng data for use with the neural_tts package.
///
/// Usage:
///   dart run neural_tts:compile_espeak_data --languages=en-us,es
void main(List<String> args) async {
  print('--- Espeak Data Compiler Helper ---');

  // Find the espeak package's compile_data script.
  // We do this instead of 'dart run espeak:compile_data' because 'dart run'
  // only works for direct dependencies. When this package is used as a 
  // dependency, 'espeak' becomes a transitive dependency and 'dart run' fails.
  //
  // We resolve a file in 'lib/' and then go up to the package root to find 'bin/'.
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:espeak/espeak.dart'),
  );

  if (libUri == null) {
    print('Error: Could not find package:espeak. Make sure it is in your dependencies.');
    exit(1);
  }

  // libUri is something like '.../espeak/lib/espeak.dart'
  // resolve('..') goes up to '.../espeak/'
  final scriptUri = libUri.resolve('../bin/compile_data.dart');
  final scriptPath = scriptUri.toFilePath();

  if (!await File(scriptPath).exists()) {
    print('Error: Could not find espeak compiler script at $scriptPath');
    exit(1);
  }

  // Get the current package configuration to pass to the sub-process.
  // This ensures that the sub-process can resolve transitive dependencies.
  final packageConfigUri = await Isolate.packageConfig;
  final List<String> dartArgs = [];
  if (packageConfigUri != null) {
    dartArgs.add('--packages=${packageConfigUri.toFilePath()}');
  }
  dartArgs.add(scriptPath);
  dartArgs.addAll(args);

  // We simply forward to the espeak:compile_data script.
  final process = await Process.start(
    'dart',
    dartArgs,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;
  if (exitCode == 0) {
    print('\nSuccessfully compiled espeak-ng data.');
    
    print('Compressing espeak-ng-data into ZIP archive...');
    try {
      final outputDir = Directory('./espeak-data');
      final dataDir = Directory('${outputDir.path}/espeak-ng-data');
      if (await dataDir.exists()) {
        final encoder = ZipFileEncoder();
        encoder.create('${outputDir.path}/espeak-ng-data.zip');
        await encoder.addDirectory(dataDir);
        encoder.close();
        print('Created: ${outputDir.path}/espeak-ng-data.zip');
      } else {
        print('Warning: espeak-ng-data directory not found, skipping compression.');
      }
    } catch (e) {
      print('Error during compression: $e');
    }

    print('\nDone. You can now host the generated "espeak-ng-data.zip" or use it in your app.');
  } else {
    print('\nFailed to compile espeak-ng data (exit code $exitCode).');
  }
}
