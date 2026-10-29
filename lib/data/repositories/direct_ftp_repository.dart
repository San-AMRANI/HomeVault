import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

import '../models/connection_settings.dart';
import '../models/nas_entry.dart';
import 'nas_repository.dart';

class DirectFtpRepository implements NasRepository {
  FTPConnect? _client;

  @override
  Future<void> connect(ConnectionSettings settings) async {
    final client = FTPConnect(
      settings.host,
      port: settings.port,
      user: settings.username,
      pass: settings.password,
      timeout: 15,
      transferMode: TransferMode.passive,
      showLog: false,
    );
    final connected = await client.connect();
    if (!connected) {
      throw const SocketException('FTP login was rejected by the server.');
    }
    _client = client;
  }

  @override
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    if (client != null) {
      await client.disconnect();
    }
  }

  FTPConnect get _connectedClient {
    final client = _client;
    if (client == null) {
      throw StateError('The FTP connection is not active.');
    }
    return client;
  }

  @override
  Future<List<NasEntry>> listDirectory(String remotePath) async {
    final path = _validateRemotePath(remotePath);
    final entries = await _connectedClient.listDirectoryContent(path);
    return entries
        .map(
          (entry) => NasEntry(
            name: entry.name,
            remotePath: _join(path, entry.name),
            type: switch (entry.type) {
              FTPEntryType.file => NasEntryType.file,
              FTPEntryType.dir => NasEntryType.directory,
              _ => NasEntryType.unknown,
            },
            sizeBytes: entry.size,
            modifiedAt: entry.modifyTime,
          ),
        )
        .toList();
  }

  @override
  Future<bool> exists(String remotePath) async {
    final path = _validateRemotePath(remotePath);
    try {
      final size = await _connectedClient.sizeFile(path);
      return size >= 0;
    } catch (_) {
      return (await listDirectory('/')).any((entry) => entry.remotePath == path);
    }
  }

  @override
  Future<int?> getRemoteSize(String remotePath) async {
    final size = await _connectedClient.sizeFile(_validateRemotePath(remotePath));
    return size < 0 ? null : size;
  }

  @override
  Future<bool> uploadFile({
    required String localPath,
    required String remoteFolder,
    required String remoteName,
    void Function(int transferred, int total)? onProgress,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw const FileSystemException('The local test file does not exist.');
    }
    await _connectedClient.changeDirectory(_validateRemotePath(remoteFolder));
    return _connectedClient.uploadFile(
      file,
      sRemoteName: _validateName(remoteName),
      onProgress: (_, transferred, total) => onProgress?.call(transferred, total),
    );
  }

  @override
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    void Function(int transferred, int total)? onProgress,
  }) async {
    final path = _validateRemotePath(remotePath);
    final separator = path.lastIndexOf('/');
    final folder = separator <= 0 ? '/' : path.substring(0, separator);
    final name = path.substring(separator + 1);
    await _connectedClient.changeDirectory(folder);
    return _connectedClient.downloadFile(
      name,
      File(localPath),
      onProgress: (_, transferred, total) => onProgress?.call(transferred, total),
    );
  }

  @override
  Future<bool> createDirectory(String remotePath) {
    return _connectedClient.makeDirectory(_validateRemotePath(remotePath));
  }

  @override
  Future<bool> rename(String oldRemotePath, String newRemotePath) {
    return _connectedClient.rename(
      _validateRemotePath(oldRemotePath),
      _validateRemotePath(newRemotePath),
    );
  }

  @override
  Future<bool> delete(String remotePath) async {
    final path = _validateRemotePath(remotePath);
    final deletedFile = await _connectedClient.deleteFile(path);
    if (deletedFile) return true;
    final deletedDirectory = await _connectedClient.deleteEmptyDirectory(path);
    if (!deletedDirectory) {
      throw UnsupportedError('The NAS denied deletion or the directory is not empty.');
    }
    return true;
  }

  String _validateRemotePath(String value) {
    final path = value.trim();
    if (path.isEmpty || !path.startsWith('/') || path.contains('..')) {
      throw ArgumentError.value(value, 'remotePath', 'Use an absolute FTP path without traversal.');
    }
    return path == '/' ? path : path.replaceAll(RegExp(r'/+'), '/').replaceFirst(RegExp(r'/$'), '');
  }

  String _validateName(String value) {
    if (value.isEmpty || value.contains('/') || value == '.' || value == '..') {
      throw ArgumentError.value(value, 'remoteName', 'Use a single remote filename.');
    }
    return value;
  }

  String _join(String folder, String name) => folder == '/' ? '/$name' : '$folder/$name';
}