import 'dart:io';

// .............................................................................
void _throw(String message, ProcessResult result) {
  if (result.exitCode != 0) {
    throw Exception('$message: ${result.stderr}');
  }
}

// .............................................................................
/// Adds and pushes local changes and creates upstream
Future<void> pushLocalChangesUpstream(Directory d, String branch) async {
  // Add local changes
  final result0 = await Process.run('git', [
    'add',
    '.',
  ], workingDirectory: d.path);
  _throw('Could not add local changes', result0);

  // Push and create upstream
  final result1 = await Process.run('git', [
    'push',
    '-u',
    'origin',
    branch,
  ], workingDirectory: d.path);
  _throw('Could not push local changes with upstream', result1);
}
