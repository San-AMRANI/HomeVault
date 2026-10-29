import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:homevault/data/models/connection_settings.dart';
import 'package:homevault/data/models/nas_entry.dart';
import 'package:homevault/data/models/transfer_task.dart';
import 'package:homevault/data/repositories/nas_repository.dart';
import 'package:homevault/services/transfer_service.dart';

void main() {
  test('upload verifies the remote size', () async {
    final repository = FakeRepository(remoteSize: 4);
    final service = TransferService(repository);
    final file = File('${Directory.systemTemp.path}/homevault-test.txt');
    await file.writeAsString('test');
    addTearDown(() => file.delete());

    final task = await service.upload(
      localPath: file.path,
      remoteFolder: '/usb1_1',
      remoteName: 'test.txt',
      conflictPolicy: ConflictPolicy.skip,
      onChanged: (_) {},
    );

    expect(task.status, TransferStatus.completed);
    expect(task.verificationStatus, VerificationStatus.sizeVerified);
  });

  test('duplicate upload is skipped and never overwritten silently', () async {
    final repository = FakeRepository(existing: true);
    final service = TransferService(repository);
    final file = File('${Directory.systemTemp.path}/homevault-duplicate.txt');
    await file.writeAsString('test');
    addTearDown(() => file.delete());

    final task = await service.upload(
      localPath: file.path,
      remoteFolder: '/usb1_1',
      remoteName: 'duplicate.txt',
      conflictPolicy: ConflictPolicy.skip,
      onChanged: (_) {},
    );

    expect(task.status, TransferStatus.cancelled);
    expect(repository.uploadCalled, isFalse);
  });
}

class FakeRepository implements NasRepository {
  FakeRepository({this.remoteSize, this.existing = false});

  final int? remoteSize;
  final bool existing;
  bool uploadCalled = false;

  @override
  Future<void> connect(ConnectionSettings settings) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> exists(String remotePath) async => existing;

  @override
  Future<int?> getRemoteSize(String remotePath) async => remoteSize;

  @override
  Future<List<NasEntry>> listDirectory(String remotePath) async => const [];

  @override
  Future<bool> createDirectory(String remotePath) async => true;

  @override
  Future<bool> rename(String oldRemotePath, String newRemotePath) async => true;

  @override
  Future<bool> delete(String remotePath) async => true;

  @override
  Future<bool> uploadFile({required String localPath, required String remoteFolder, required String remoteName, void Function(int transferred, int total)? onProgress}) async {
    uploadCalled = true;
    onProgress?.call(4, 4);
    return true;
  }

  @override
  Future<bool> downloadFile({required String remotePath, required String localPath, void Function(int transferred, int total)? onProgress}) async => true;
}