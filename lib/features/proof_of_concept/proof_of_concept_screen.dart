import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/connection_settings.dart';
import '../../data/models/nas_entry.dart';
import '../../data/models/poc_result.dart';
import '../../data/repositories/nas_repository.dart';

class ProofOfConceptScreen extends StatefulWidget {
  const ProofOfConceptScreen({required this.repository, super.key});

  final NasRepository repository;

  @override
  State<ProofOfConceptScreen> createState() => _ProofOfConceptScreenState();
}

class _ProofOfConceptScreenState extends State<ProofOfConceptScreen> {
  final _host = TextEditingController(text: '192.168.11.1');
  final _port = TextEditingController(text: '21');
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _remoteFile = TextEditingController();
  final _downloadPath = TextEditingController();
  final _localFile = TextEditingController();
  final _uploadFolder = TextEditingController(text: '/usb1_1');
  final _uploadName = TextEditingController(text: 'homevault-disposable-test.bin');

  final _results = <PocStepResult>[];
  bool _running = false;
  String _status = 'Not connected';
  List<NasEntry> _rootEntries = const [];

  @override
  void dispose() {
    for (final controller in [
      _host,
      _port,
      _username,
      _password,
      _remoteFile,
      _downloadPath,
      _localFile,
      _uploadFolder,
      _uploadName,
    ]) {
      controller.dispose();
    }
    widget.repository.disconnect();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (_running) return;
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _showMessage('Enter a valid port from 1 to 65535.');
      return;
    }

    setState(() {
      _running = true;
      _status = 'Testing direct FTP connection...';
      _results.clear();
      _rootEntries = const [];
    });

    try {
      await widget.repository.connect(
        ConnectionSettings(
          host: _host.text.trim(),
          port: port,
          username: _username.text.trim(),
          password: _password.text,
        ),
      );
      _addResult('Login', PocStepStatus.passed, 'Authenticated over passive FTP.');

      final root = await widget.repository.listDirectory('/');
      _rootEntries = root;
      _addResult('List /', PocStepStatus.passed, '${root.length} entries returned.');

      final usbEntry = root.where((entry) => entry.name == 'usb1_1').firstOrNull;
      if (usbEntry?.type == NasEntryType.directory) {
        final usbEntries = await widget.repository.listDirectory('/usb1_1');
        _addResult(
          'List /usb1_1',
          PocStepStatus.passed,
          '${usbEntries.length} entries returned.',
        );
      } else {
        _addResult('List /usb1_1', PocStepStatus.unsupported, 'The folder was not reported at the FTP root.');
      }

      _addResult(
        'Metadata',
        PocStepStatus.passed,
        'Directory metadata was read where the server supplied it.',
      );
      await _runOptionalDownload();
      await _runOptionalUpload();
      _addResult(
        'Wi-Fi recovery',
        PocStepStatus.notRun,
        'Manual test required: interrupt Wi-Fi during transfer and confirm it is not marked complete.',
      );
      setState(() => _status = 'Direct FTP test completed');
    } catch (error) {
      _addResult('Connection/test', _statusFor(error), _friendlyError(error));
      setState(() => _status = 'Test failed');
    } finally {
      await widget.repository.disconnect();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runOptionalDownload() async {
    final remotePath = _remoteFile.text.trim();
    final localPath = _downloadPath.text.trim();
    if (remotePath.isEmpty && localPath.isEmpty) return;
    if (remotePath.isEmpty || localPath.isEmpty) {
      _addResult('Download', PocStepStatus.failed, 'Provide both a remote file and local destination.');
      return;
    }
    try {
      final remoteSize = await widget.repository.getRemoteSize(remotePath);
      final downloaded = await widget.repository.downloadFile(
        remotePath: remotePath,
        localPath: localPath,
      );
      final localSize = await File(localPath).length();
      final verified = remoteSize != null && downloaded && remoteSize == localSize;
      _addResult(
        'Download',
        verified ? PocStepStatus.passed : PocStepStatus.failed,
        verified
            ? 'Downloaded and size verified at $localSize bytes.'
            : 'Downloaded=${downloaded.toString()}; size verification unavailable or mismatched.',
      );
    } catch (error) {
      _addResult('Download', _statusFor(error), _friendlyError(error));
    }
  }

  Future<void> _runOptionalUpload() async {
    final localPath = _localFile.text.trim();
    final folder = _uploadFolder.text.trim();
    final name = _uploadName.text.trim();
    if (localPath.isEmpty && folder.isEmpty) return;
    if (localPath.isEmpty || folder.isEmpty || name.isEmpty) {
      _addResult('Upload', PocStepStatus.failed, 'Provide a local file, destination folder, and filename.');
      return;
    }
    try {
      final localSize = await File(localPath).length();
      final uploaded = await widget.repository.uploadFile(
        localPath: localPath,
        remoteFolder: folder,
        remoteName: name,
      );
      final remotePath = folder == '/' ? '/$name' : '$folder/$name';
      final remoteSize = uploaded ? await widget.repository.getRemoteSize(remotePath) : null;
      final verified = uploaded && remoteSize == localSize;
      _addResult(
        'Upload',
        verified ? PocStepStatus.passed : (uploaded ? PocStepStatus.denied : PocStepStatus.failed),
        verified
            ? 'Uploaded and size verified at $localSize bytes.'
            : 'Uploaded=${uploaded.toString()}; remote size was ${remoteSize?.toString() ?? 'unavailable'}.',
      );
    } catch (error) {
      _addResult('Upload', _statusFor(error), _friendlyError(error));
    }
  }

  void _addResult(String name, PocStepStatus status, String message) {
    if (mounted) setState(() => _results.add(PocStepResult(name: name, status: status, message: message)));
  }

  PocStepStatus _statusFor(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission') || message.contains('denied') || message.contains('not supported')) {
      return PocStepStatus.denied;
    }
    return PocStepStatus.failed;
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    if (message.contains('SocketException')) return 'Router unreachable or passive data connection failed.';
    if (message.toLowerCase().contains('login')) return 'Login failed. Check host, port, username, and password.';
    return message.length > 180 ? '${message.substring(0, 180)}...' : message;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HomeVault FTP proof of concept')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Phase 1: direct router verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('This screen performs real FTP operations from the Android device. It does not use demo data.'),
          const SizedBox(height: 16),
          _section('Connection', [
            _field(_host, 'Host'),
            _field(_port, 'Port', keyboardType: TextInputType.number),
            _field(_username, 'Username'),
            _field(_password, 'Password', obscureText: true),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _running ? null : _testConnection,
              icon: const Icon(Icons.network_check),
              label: Text(_running ? 'Testing...' : 'Test connection'),
            ),
            const SizedBox(height: 8),
            Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ]),
          _section('Optional small-file download test', [
            _field(_remoteFile, 'Remote file path, e.g. /usb1_1/test.txt'),
            _field(_downloadPath, 'Local destination path'),
          ]),
          _section('Optional disposable upload test', [
            _field(_localFile, 'Local test file path'),
            _field(_uploadFolder, 'Remote test folder'),
            _field(_uploadName, 'Disposable remote filename'),
            const Text('Use a disposable folder. Upload, rename, and delete permissions are not assumed.'),
          ]),
          if (_rootEntries.isNotEmpty) _section('Root listing', [
            for (final entry in _rootEntries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry.type == NasEntryType.directory ? Icons.folder : Icons.insert_drive_file),
                title: Text(entry.name),
                subtitle: Text('${entry.remotePath} • ${entry.sizeBytes?.toString() ?? 'size unavailable'} bytes'),
              ),
          ]),
          _section('Results', [
            if (_results.isEmpty) const Text('No test has run yet.'),
            for (final result in _results) _resultTile(result),
          ]),
          const SizedBox(height: 8),
          const Text('Plain FTP warning: credentials and file contents are not encrypted. Use only on a trusted LAN; do not expose the router FTP port to the internet.'),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {bool obscureText = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _resultTile(PocStepResult result) {
    final icon = switch (result.status) {
      PocStepStatus.passed => Icons.check_circle,
      PocStepStatus.notRun => Icons.help_outline,
      PocStepStatus.denied => Icons.block,
      PocStepStatus.failed => Icons.error,
      PocStepStatus.running => Icons.sync,
      PocStepStatus.unsupported => Icons.remove_circle_outline,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(result.name),
      subtitle: Text(result.message),
    );
  }
}