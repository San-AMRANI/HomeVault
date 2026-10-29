import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/models/app_settings.dart';

class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage}) : _storage = storage ?? FlutterSecureStorage();

  static const _hostKey = 'ftp.host';
  static const _portKey = 'ftp.port';
  static const _usernameKey = 'ftp.username';
  static const _passwordKey = 'ftp.password';

  final FlutterSecureStorage _storage;

  Future<AppSettings> readSettings() async {
    final host = await _storage.read(key: _hostKey);
    final port = int.tryParse(await _storage.read(key: _portKey) ?? '');
    final username = await _storage.read(key: _usernameKey);
    return AppSettings(
      host: host?.isNotEmpty == true ? host! : '192.168.11.1',
      port: port ?? 21,
      username: username?.isNotEmpty == true ? username! : 'admin',
    );
  }

  Future<void> writeSettings(AppSettings settings, String password) async {
    await Future.wait([
      _storage.write(key: _hostKey, value: settings.host),
      _storage.write(key: _portKey, value: settings.port.toString()),
      _storage.write(key: _usernameKey, value: settings.username),
      _storage.write(key: _passwordKey, value: password),
    ]);
  }

  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  Future<void> clearCredentials() async {
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _usernameKey);
  }
}