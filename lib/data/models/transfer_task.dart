enum TransferDirection { upload, download }

enum TransferStatus { queued, connecting, uploading, downloading, verifying, completed, failed, cancelled }

enum VerificationStatus { notAttempted, sizeVerified, failed, unsupported }

class TransferTask {
  TransferTask({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.source,
    required this.remotePath,
    this.totalBytes,
  }) : createdAt = DateTime.now();

  final String id;
  final TransferDirection direction;
  final String fileName;
  final String source;
  final String remotePath;
  final int? totalBytes;
  final DateTime createdAt;
  DateTime? finishedAt;
  int transferredBytes = 0;
  TransferStatus status = TransferStatus.queued;
  VerificationStatus verificationStatus = VerificationStatus.notAttempted;
  String? errorMessage;

  double? get progress => totalBytes == null || totalBytes == 0 ? null : transferredBytes / totalBytes!;
}