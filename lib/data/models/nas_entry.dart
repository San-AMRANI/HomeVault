enum NasEntryType { file, directory, unknown }

class NasEntry {
  const NasEntry({
    required this.name,
    required this.remotePath,
    required this.type,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String name;
  final String remotePath;
  final NasEntryType type;
  final int? sizeBytes;
  final DateTime? modifiedAt;
}