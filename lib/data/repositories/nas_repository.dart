import '../models/connection_settings.dart';
import '../models/nas_entry.dart';

abstract interface class NasRepository {
  Future<void> connect(ConnectionSettings settings);

  Future<void> disconnect();

  Future<List<NasEntry>> listDirectory(String remotePath);

  Future<bool> exists(String remotePath);

  Future<int?> getRemoteSize(String remotePath);

  Future<bool> uploadFile({
    required String localPath,
    required String remoteFolder,
    required String remoteName,
    void Function(int transferred, int total)? onProgress,
  });

  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    void Function(int transferred, int total)? onProgress,
  });

  Future<bool> createDirectory(String remotePath);

  Future<bool> rename(String oldRemotePath, String newRemotePath);

  Future<bool> delete(String remotePath);
}