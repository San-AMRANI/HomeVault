import 'dart:io';

import '../data/models/transfer_task.dart';
import '../data/repositories/nas_repository.dart';

class TransferService {
  TransferService(this.repository);

  final NasRepository repository;

  Future<TransferTask> upload({
    required String localPath,
    required String remoteFolder,
    required String remoteName,
    required ConflictPolicy conflictPolicy,
    required void Function(TransferTask task) onChanged,
  }) async {
    final file = File(localPath);
    var effectiveName = remoteName;
    if (conflictPolicy == ConflictPolicy.rename) {
      var suffix = 1;
      while (await repository.exists(remoteFolder == '/' ? '/$effectiveName' : '$remoteFolder/$effectiveName')) {
        final dot = remoteName.lastIndexOf('.');
        final stem = dot > 0 ? remoteName.substring(0, dot) : remoteName;
        final extension = dot > 0 ? remoteName.substring(dot) : '';
        effectiveName = '$stem ($suffix)$extension';
        suffix++;
      }
    }
    final task = TransferTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-$effectiveName',
      direction: TransferDirection.upload,
      fileName: effectiveName,
      source: localPath,
      remotePath: remoteFolder == '/' ? '/$effectiveName' : '$remoteFolder/$effectiveName',
      totalBytes: await file.length(),
    );
    onChanged(task);
    try {
      task.status = TransferStatus.connecting;
      onChanged(task);
      if (await repository.exists(task.remotePath)) {
        if (conflictPolicy == ConflictPolicy.skip) {
          task.status = TransferStatus.cancelled;
          task.errorMessage = 'Skipped because the destination already exists.';
          return _finish(task, onChanged);
        }
        if (conflictPolicy == ConflictPolicy.rename) {
          throw StateError('A unique destination name could not be selected.');
        }
      }
      task.status = TransferStatus.uploading;
      onChanged(task);
      final uploaded = await repository.uploadFile(
        localPath: localPath,
        remoteFolder: remoteFolder,
        remoteName: effectiveName,
        onProgress: (transferred, _) {
          task.transferredBytes = transferred;
          onChanged(task);
        },
      );
      if (!uploaded) throw const FileSystemException('The NAS rejected the upload.');
      task.status = TransferStatus.verifying;
      onChanged(task);
      final remoteSize = await repository.getRemoteSize(task.remotePath);
      if (remoteSize == task.totalBytes) {
        task.verificationStatus = VerificationStatus.sizeVerified;
      } else if (remoteSize == null) {
        task.verificationStatus = VerificationStatus.unsupported;
      } else {
        task.verificationStatus = VerificationStatus.failed;
        throw const FileSystemException('Remote size does not match the local file.');
      }
      task.transferredBytes = task.totalBytes ?? task.transferredBytes;
      task.status = TransferStatus.completed;
    } catch (error) {
      task.status = TransferStatus.failed;
      task.errorMessage = _safeMessage(error);
    }
    return _finish(task, onChanged);
  }

  Future<TransferTask> download({
    required String remotePath,
    required String localPath,
    required void Function(TransferTask task) onChanged,
  }) async {
    final name = remotePath.split('/').last;
    final task = TransferTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-$name',
      direction: TransferDirection.download,
      fileName: name,
      source: remotePath,
      remotePath: remotePath,
      totalBytes: await repository.getRemoteSize(remotePath),
    );
    onChanged(task);
    try {
      task.status = TransferStatus.downloading;
      onChanged(task);
      final downloaded = await repository.downloadFile(
        remotePath: remotePath,
        localPath: localPath,
        onProgress: (transferred, _) {
          task.transferredBytes = transferred;
          onChanged(task);
        },
      );
      if (!downloaded) throw const FileSystemException('The NAS rejected the download.');
      final localSize = await File(localPath).length();
      if (task.totalBytes != null && task.totalBytes == localSize) {
        task.verificationStatus = VerificationStatus.sizeVerified;
      } else if (task.totalBytes == null) {
        task.verificationStatus = VerificationStatus.unsupported;
      } else {
        task.verificationStatus = VerificationStatus.failed;
        throw const FileSystemException('Downloaded size does not match the NAS file.');
      }
      task.transferredBytes = localSize;
      task.status = TransferStatus.completed;
    } catch (error) {
      task.status = TransferStatus.failed;
      task.errorMessage = _safeMessage(error);
    }
    return _finish(task, onChanged);
  }

  TransferTask _finish(TransferTask task, void Function(TransferTask task) onChanged) {
    task.finishedAt = DateTime.now();
    onChanged(task);
    return task;
  }

  String _safeMessage(Object error) {
    final value = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    if (value.contains('SocketException')) return 'Router unreachable or the Wi-Fi data connection failed.';
    return value.length > 180 ? '${value.substring(0, 180)}...' : value;
  }
}

enum ConflictPolicy { skip, rename, overwrite }