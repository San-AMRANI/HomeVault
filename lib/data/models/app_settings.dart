class AppSettings {
  const AppSettings({
    this.host = '192.168.11.1',
    this.port = 21,
    this.username = 'admin',
  });

  final String host;
  final int port;
  final String username;

  AppSettings copyWith({String? host, int? port, String? username}) {
    return AppSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
    );
  }
}