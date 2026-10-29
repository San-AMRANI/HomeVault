import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'data/models/app_settings.dart';
import 'data/models/connection_settings.dart';
import 'data/models/nas_entry.dart';
import 'data/models/transfer_task.dart';
import 'data/repositories/direct_ftp_repository.dart';
import 'data/repositories/nas_repository.dart';
import 'services/secure_storage_service.dart';
import 'services/transfer_service.dart';

class HomeVaultApp extends StatefulWidget {
  const HomeVaultApp({super.key});

  @override
  State<HomeVaultApp> createState() => _HomeVaultAppState();
}

class _HomeVaultAppState extends State<HomeVaultApp> {
  late final HomeVaultController controller;

  @override
  void initState() {
    super.initState();
    controller = HomeVaultController(DirectFtpRepository(), SecureStorageService())..load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HomeVault',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b87)), useMaterial3: true),
        darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff79d4de), brightness: Brightness.dark), useMaterial3: true),
        themeMode: ThemeMode.system,
        home: HomeVaultShell(controller: controller),
      );
}

class HomeVaultController extends ChangeNotifier {
  HomeVaultController(this.repository, this.storage);

  final NasRepository repository;
  final SecureStorageService storage;
  late final TransferService transferService = TransferService(repository);
  AppSettings settings = const AppSettings();
  String password = '';
  List<NasEntry> entries = const [];
  final List<TransferTask> transfers = [];
  String currentPath = '/';
  String status = 'Set up your Home NAS connection.';
  bool loading = true;
  bool busy = false;
  bool connected = false;
  int tab = 0;

  Future<void> load() async {
    settings = await storage.readSettings();
    password = await storage.readPassword() ?? '';
    loading = false;
    notifyListeners();
  }

  void setTab(int value) {
    tab = value;
    notifyListeners();
  }

  void updateSettings(AppSettings value, String newPassword) {
    settings = value;
    password = newPassword;
    notifyListeners();
  }

  Future<void> clearCredentials() async {
    await storage.clearCredentials();
    password = '';
    status = 'Saved credentials cleared';
    notifyListeners();
  }

  Future<bool> connect({bool persist = true}) async {
    if (busy) return false;
    busy = true;
    status = 'Connecting directly to ${settings.host}:${settings.port}...';
    notifyListeners();
    try {
      await repository.connect(ConnectionSettings(host: settings.host, port: settings.port, username: settings.username, password: password));
      connected = true;
      entries = await repository.listDirectory('/');
      currentPath = '/';
      if (persist) await storage.writeSettings(settings, password);
      status = 'Connected to local NAS';
      return true;
    } catch (error) {
      connected = false;
      status = _friendlyError(error);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await repository.disconnect();
    connected = false;
    entries = const [];
    currentPath = '/';
    status = 'Disconnected';
    notifyListeners();
  }

  Future<void> browse(String path) async {
    if (!connected) return;
    busy = true;
    notifyListeners();
    try {
      entries = await repository.listDirectory(path);
      currentPath = path;
      status = 'Showing $path';
    } catch (error) {
      status = _friendlyError(error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> createFolder(String name) async {
    final path = currentPath == '/' ? '/$name' : '$currentPath/$name';
    try {
      final created = await repository.createDirectory(path);
      status = created ? 'Folder created' : 'The NAS did not create the folder';
      await browse(currentPath);
    } catch (error) {
      status = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> rename(NasEntry entry, String name) async {
    final destination = currentPath == '/' ? '/$name' : '$currentPath/$name';
    try {
      final renamed = await repository.rename(entry.remotePath, destination);
      status = renamed ? 'Renamed ${entry.name}' : 'Rename was denied by the NAS';
      await browse(currentPath);
    } catch (error) {
      status = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> delete(NasEntry entry) async {
    try {
      final deleted = await repository.delete(entry.remotePath);
      status = deleted ? 'Deleted ${entry.name}' : 'Delete was denied by the NAS';
      await browse(currentPath);
    } catch (error) {
      status = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> addUpload(String path, String folder, String name, ConflictPolicy policy) async {
    final task = await transferService.upload(localPath: path, remoteFolder: folder, remoteName: name, conflictPolicy: policy, onChanged: _trackTransfer);
    status = task.status == TransferStatus.completed ? 'Upload completed' : 'Upload ${task.status.name}';
    notifyListeners();
  }

  Future<void> addDownload(String remotePath, String destination) async {
    final task = await transferService.download(remotePath: remotePath, localPath: destination, onChanged: _trackTransfer);
    status = task.status == TransferStatus.completed ? 'Download completed' : 'Download ${task.status.name}';
    notifyListeners();
  }

  void _trackTransfer(TransferTask task) {
    final index = transfers.indexWhere((item) => item.id == task.id);
    if (index == -1) {
      transfers.insert(0, task);
    } else {
      transfers[index] = task;
    }
    notifyListeners();
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    if (text.contains('SocketException')) return 'Router unreachable or Wi-Fi data connection failed.';
    if (text.toLowerCase().contains('login')) return 'Login failed. Check the connection details.';
    return text.length > 180 ? '${text.substring(0, 180)}...' : text;
  }
}

class HomeVaultShell extends StatelessWidget {
  const HomeVaultShell({required this.controller, super.key});
  final HomeVaultController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (!controller.connected && controller.tab != 3) return ConnectionPage(controller: controller);
          final pages = [DashboardPage(controller: controller), FilesPage(controller: controller), TransfersPage(controller: controller), SettingsPage(controller: controller)];
          return Scaffold(
            body: SafeArea(child: pages[controller.tab]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: controller.tab,
              onDestinationSelected: controller.setTab,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Files'),
                NavigationDestination(icon: Icon(Icons.swap_vert), label: 'Transfers'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          );
        },
      );
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({required this.controller, super.key});
  final HomeVaultController controller;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final TextEditingController host = TextEditingController(text: widget.controller.settings.host);
  late final TextEditingController port = TextEditingController(text: widget.controller.settings.port.toString());
  late final TextEditingController username = TextEditingController(text: widget.controller.settings.username);
  late final TextEditingController password = TextEditingController(text: widget.controller.password);

  @override
  void dispose() {
    host.dispose();
    port.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final parsedPort = int.tryParse(port.text);
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) return;
    widget.controller.updateSettings(widget.controller.settings.copyWith(host: host.text.trim(), port: parsedPort, username: username.text.trim()), password.text);
    await widget.controller.connect();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              const Icon(Icons.storage_rounded, size: 64),
              const SizedBox(height: 12),
              Text('Connect to your Home NAS', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('HomeVault connects directly from this phone to your router over local FTP.'),
              const SizedBox(height: 24),
              _input(host, 'Host'),
              _input(port, 'Port', type: TextInputType.number),
              _input(username, 'Username'),
              _input(password, 'Password', obscure: true),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: widget.controller.busy ? null : submit, icon: const Icon(Icons.link), label: const Text('Test connection')),
              const SizedBox(height: 12),
              Text(widget.controller.status),
              const SizedBox(height: 24),
              const Text('Plain FTP is not encrypted. Use only on a trusted local network and never expose the router FTP port to the internet.'),
            ],
          ),
        ),
      );

  Widget _input(TextEditingController controller, String label, {bool obscure = false, TextInputType? type}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller, obscureText: obscure, keyboardType: type, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.controller, super.key});
  final HomeVaultController controller;

  @override
  Widget build(BuildContext context) {
    final completed = controller.transfers.where((task) => task.status == TransferStatus.completed).length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('HomeVault', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text(controller.status),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: () => _pickUploads(context), icon: const Icon(Icons.backup), label: const Text('Back up files')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () => controller.setTab(1), icon: const Icon(Icons.folder), label: const Text('Browse Home NAS')),
      const SizedBox(height: 24),
      ListTile(leading: const Icon(Icons.cloud_done_outlined), title: const Text('Local NAS connection'), subtitle: Text('${controller.settings.host}:${controller.settings.port}')),
      ListTile(leading: const Icon(Icons.check_circle_outline), title: const Text('Completed transfers'), trailing: Text('$completed')),
      const SizedBox(height: 12),
      const Text('Capacity information unavailable until the router exposes a reliable capacity API.'),
    ]);
  }

  Future<void> _pickUploads(BuildContext context) async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final paths = files.map((file) => file.path).whereType<String>().toList();
    if (paths.length != files.length) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('One or more picker handles could not be opened on this device.')));
      return;
    }
    if (!context.mounted) return;
    final destination = await _destinationDialog(context, controller);
    if (destination == null) return;
    if (!context.mounted) return;
    final policy = await _conflictDialog(context);
    if (policy == null) return;
    for (final path in paths) {
      await controller.addUpload(path, destination, path.split('/').last, policy);
    }
  }
}

class FilesPage extends StatelessWidget {
  const FilesPage({required this.controller, super.key});
  final HomeVaultController controller;

  @override
  Widget build(BuildContext context) => Column(children: [
        AppBar(title: Text(controller.currentPath), actions: [IconButton(onPressed: controller.busy ? null : () => controller.browse(controller.currentPath), icon: const Icon(Icons.refresh), tooltip: 'Refresh'), IconButton(onPressed: () => _newFolder(context), icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New folder')]),
        if (controller.currentPath != '/') Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => controller.browse(_parent(controller.currentPath)), icon: const Icon(Icons.arrow_upward), label: const Text('Up'))),
        Expanded(child: controller.busy ? const Center(child: CircularProgressIndicator()) : controller.entries.isEmpty ? const Center(child: Text('This folder is empty.')) : ListView.builder(itemCount: controller.entries.length, itemBuilder: (context, index) => _entryTile(context, controller.entries[index]))),
      ]);

  Widget _entryTile(BuildContext context, NasEntry entry) {
    final folder = entry.type == NasEntryType.directory;
    return ListTile(leading: Icon(folder ? Icons.folder : Icons.insert_drive_file), title: Text(entry.name), subtitle: Text('${entry.sizeBytes == null ? 'Size unavailable' : _size(entry.sizeBytes!)}${entry.modifiedAt == null ? '' : ' • ${entry.modifiedAt}'}'), onTap: folder ? () => controller.browse(entry.remotePath) : () => _fileActions(context, entry));
  }

  Future<void> _fileActions(BuildContext context, NasEntry entry) async {
    final action = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Wrap(children: [ListTile(leading: const Icon(Icons.download), title: const Text('Download'), onTap: () => Navigator.pop(context, 'download')), ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Rename'), onTap: () => Navigator.pop(context, 'rename')), ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'), onTap: () => Navigator.pop(context, 'delete'))])));
    if (!context.mounted || action == null) return;
    if (action == 'download') {
      final directory = await FilePicker.getDirectoryPath(dialogTitle: 'Choose download folder');
      if (directory != null) await controller.addDownload(entry.remotePath, '$directory/${entry.name}');
    } else if (action == 'rename') {
      final name = await _textDialog(context, 'Rename', entry.name);
      if (name != null && name.isNotEmpty) await controller.rename(entry, name);
    } else if (action == 'delete' && await _confirm(context, 'Delete ${entry.name}?')) {
      await controller.delete(entry);
    }
  }

  Future<void> _newFolder(BuildContext context) async {
    final name = await _textDialog(context, 'New folder', 'Folder name');
    if (name != null && name.isNotEmpty) await controller.createFolder(name);
  }
}

class TransfersPage extends StatelessWidget {
  const TransfersPage({required this.controller, super.key});
  final HomeVaultController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.transfers.isEmpty) return const Center(child: Text('No transfers yet.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Transfers', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      for (final task in controller.transfers) _transferTile(task),
    ]);
  }

  Widget _transferTile(TransferTask task) {
    final progress = task.progress;
    return ListTile(leading: Icon(task.direction == TransferDirection.upload ? Icons.upload : Icons.download), title: Text(task.fileName), subtitle: Text('${task.status.name} • ${task.verificationStatus.name}${task.errorMessage == null ? '' : ' • ${task.errorMessage}'}'), trailing: progress == null ? null : SizedBox(width: 56, child: CircularProgressIndicator(value: progress)));
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});
  final HomeVaultController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController host = TextEditingController(text: widget.controller.settings.host);
  late final TextEditingController port = TextEditingController(text: widget.controller.settings.port.toString());
  late final TextEditingController username = TextEditingController(text: widget.controller.settings.username);
  late final TextEditingController password = TextEditingController(text: widget.controller.password);

  @override
  void dispose() {
    host.dispose();
    port.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _input(host, 'Host'),
        _input(port, 'Port'),
        _input(username, 'Username'),
        _input(password, 'Password', obscure: true),
        FilledButton(onPressed: () async { final portNumber = int.tryParse(port.text); if (portNumber != null) { widget.controller.updateSettings(widget.controller.settings.copyWith(host: host.text.trim(), port: portNumber, username: username.text.trim()), password.text); await widget.controller.connect(); } }, child: const Text('Save and test connection')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () async { await widget.controller.clearCredentials(); password.clear(); }, child: const Text('Clear saved credentials')),
        const SizedBox(height: 24),
        const ListTile(leading: Icon(Icons.warning_amber), title: Text('Plain FTP security'), subtitle: Text('FTP credentials and file contents are sent without encryption. Use only on a trusted LAN. FTPS and SFTP are different protocols and are not enabled by this default FTP connection.')),
        ListTile(leading: const Icon(Icons.link_off), title: const Text('Connection'), subtitle: Text(widget.controller.status), trailing: TextButton(onPressed: widget.controller.connected ? widget.controller.disconnect : null, child: const Text('Disconnect'))),
      ]);

  Widget _input(TextEditingController controller, String label, {bool obscure = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller, obscureText: obscure, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
}

String _parent(String path) {
  final index = path.lastIndexOf('/');
  return index <= 0 ? '/' : path.substring(0, index);
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

Future<String?> _destinationDialog(BuildContext context, HomeVaultController controller) async => showDialog<String>(context: context, builder: (context) { final pathController = TextEditingController(text: controller.currentPath == '/' ? '/usb1_1' : controller.currentPath); final folders = controller.entries.where((entry) => entry.type == NasEntryType.directory).toList(); return AlertDialog(title: const Text('NAS destination'), content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: [for (final folder in folders) ListTile(leading: const Icon(Icons.folder), title: Text(folder.name), subtitle: Text(folder.remotePath), onTap: () => Navigator.pop(context, folder.remotePath)), TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Remote folder path', border: OutlineInputBorder()))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, pathController.text.trim()), child: const Text('Use folder'))]); });

Future<ConflictPolicy?> _conflictDialog(BuildContext context) async => showDialog<ConflictPolicy>(context: context, builder: (context) => AlertDialog(title: const Text('Duplicate names'), content: const Text('Choose what to do if a destination already exists. Overwrite requires this explicit choice and is never automatic.'), actions: [TextButton(onPressed: () => Navigator.pop(context, ConflictPolicy.skip), child: const Text('Skip')), TextButton(onPressed: () => Navigator.pop(context, ConflictPolicy.rename), child: const Text('Rename')), FilledButton(onPressed: () => Navigator.pop(context, ConflictPolicy.overwrite), child: const Text('Overwrite'))]));

Future<String?> _textDialog(BuildContext context, String title, String initial) async => showDialog<String>(context: context, builder: (context) { final controller = TextEditingController(text: initial == 'Folder name' ? '' : initial); return AlertDialog(title: Text(title), content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: initial)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save'))]); });

Future<bool> _confirm(BuildContext context, String message) async => (await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Confirm'), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))]))) ?? false;