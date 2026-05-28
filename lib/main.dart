import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math'; // Added for log and pow

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BitNexusApp());
}

class BitNexusApp extends StatelessWidget {
  const BitNexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BitNexus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00FF87),
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        cardColor: const Color(0xFF16161E),
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF87),
          secondary: Color(0xFF00B8D4),
          surface: Color(0xFF16161E),
          background: Color(0xFF0A0A0C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF00FF87),
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FF87),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1F1F26),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00FF87), width: 2),
          ),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
      ),
      home: const MainWorkspaceHub(),
    );
  }
}

// --- QBitManager Service ---
class QBitManager {
  static String baseUrl = "http://localhost:8080";
  static String username = "";
  static String password = "";
  static String? _cookie;

  static Future<void> saveSettings(String url, String user, String pass) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('qb_url', url);
    await prefs.setString('qb_user', user);
    await prefs.setString('qb_pass', pass);
    baseUrl = url;
    username = user;
    password = pass;
  }

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('qb_url') ?? "http://localhost:8080";
    username = prefs.getString('qb_user') ?? "";
    password = prefs.getString('qb_pass') ?? "";
  }

  static Future<bool> login() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v2/auth/login'),
        body: {'username': username, 'password': password},
      );
      if (response.statusCode == 200 && response.body == "Ok.") {
        // Extract cookie from headers
        final setCookie = response.headers['set-cookie'];
        if (setCookie != null) {
          _cookie = setCookie.split(';')[0];
        }
        return true;
      }
      return false;
    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  static Map<String, String> get _headers {
    return {
      'Cookie': _cookie ?? '',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  static Future<bool> addTorrent(String magnetLink, bool sequential) async {
    await login(); // Ensure logged in
    
    // 1. Add Torrent
    final addResponse = await http.post(
      Uri.parse('$baseUrl/api/v2/torrents/add'),
      headers: _headers,
      body: {'urls': magnetLink},
    );

    if (addResponse.statusCode != 200) return false;

    // 2. Wait a moment for hash to register, then set Sequential
    final hashMatch = RegExp(r'xt=urn:btih:([a-zA-Z0-9]+)').firstMatch(magnetLink);
    if (hashMatch != null && sequential) {
      final hash = hashMatch.group(1)!.toLowerCase();
      await Future.delayed(const Duration(milliseconds: 500));
      
      await http.post(
        Uri.parse('$baseUrl/api/v2/torrents/setSequentialDownload'),
        headers: _headers,
        body: {'ids': hash, 'value': 'true'},
      );
    }
    return true;
  }

  static Future<List<dynamic>> getTorrents() async {
    await login();
    final response = await http.get(
      Uri.parse('$baseUrl/api/v2/torrents/info'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return [];
  }
}

class MainWorkspaceHub extends StatefulWidget {
  const MainWorkspaceHub({super.key});

  @override
  State<MainWorkspaceHub> createState() => _MainWorkspaceHubState();
}

class _MainWorkspaceHubState extends State<MainWorkspaceHub> with SingleTickerProviderStateMixin {
  String currentServer = "http://127.0.0.1:5000"; // Index Server
  List<dynamic> indexTorrents = [];
  List<dynamic> activeDownloads = []; // From qBittorrent
  bool isLoadingIndex = false;
  bool isLoadingDownloads = false;
  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _serverController = TextEditingController(text: "http://127.0.0.1:5000");
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _magnetController = TextEditingController();
  
  // Settings Controllers
  final TextEditingController _qbUrlController = TextEditingController();
  final TextEditingController _qbUserController = TextEditingController();
  final TextEditingController _qbPassController = TextEditingController();

  String _selectedCategory = "Anime";
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _loadSavedSettings();
    fetchIndexFeed();
    refreshDownloads();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSettings() async {
    await QBitManager.loadSettings();
    setState(() {
      _qbUrlController.text = QBitManager.baseUrl;
      _qbUserController.text = QBitManager.username;
      _qbPassController.text = QBitManager.password;
    });
  }

  // --- Index Feed Logic ---
  Future<void> fetchIndexFeed() async {
    setState(() => isLoadingIndex = true);
    try {
      final query = _searchController.text.trim();
      final response = await http.get(
        Uri.parse("$currentServer/api/feed?q=$query"),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          indexTorrents = json.decode(response.body);
          isLoadingIndex = false;
        });
        _animationController.forward(from: 0.0);
      } else {
        throw Exception('Failed to load');
      }
    } catch (_) {
      setState(() {
        indexTorrents = [];
        isLoadingIndex = false;
      });
      _showSnackbar("Index Node Offline", isError: true);
    }
  }

  // --- qBittorrent Logic ---
  Future<void> refreshDownloads() async {
    setState(() => isLoadingDownloads = true);
    try {
      final torrents = await QBitManager.getTorrents();
      setState(() {
        activeDownloads = torrents;
        isLoadingDownloads = false;
      });
    } catch (e) {
      setState(() => isLoadingDownloads = false);
    }
  }

  Future<void> startSmartDownload(String magnetLink, String title) async {
    _showSnackbar("Adding to qBittorrent (Sequential Mode)...");
    
    final success = await QBitManager.addTorrent(magnetLink, true);
    
    if (success) {
      _showSnackbar("Started: $title");
      refreshDownloads();
      setState(() => _selectedIndex = 1); // Switch to Downloads tab
    } else {
      _showSnackbar("Failed to connect to qBittorrent. Check Settings.", isError: true);
    }
  }

  // --- Upload Logic ---
  Future<void> submitRelease() async {
    final title = _titleController.text.trim();
    final infoHash = _hashController.text.trim().toLowerCase();
    final size = _sizeController.text.trim().isEmpty ? "Unknown" : _sizeController.text.trim();

    if (title.isEmpty || infoHash.length != 40) {
      _showSnackbar("Title and valid 40-char Hash required", isError: true);
      return;
    }

    final generatedMagnet = "magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}";
    setState(() => isLoadingIndex = true);

    try {
      final response = await http.post(
        Uri.parse("$currentServer/api/submit"),
        body: {
          "title": title,
          "info_hash": infoHash,
          "magnet_link": generatedMagnet,
          "category": _selectedCategory,
          "size": size
        },
      );

      if (response.statusCode == 200) {
        _titleController.clear();
        _hashController.clear();
        _sizeController.clear();
        _magnetController.clear();
        _showSnackbar("Release Published!");
        setState(() => _selectedIndex = 0);
        fetchIndexFeed();
      } else {
        _showSnackbar("Server Error: ${response.statusCode}", isError: true);
      }
    } catch (_) {
      _showSnackbar("Network Error", isError: true);
    } finally {
      setState(() => isLoadingIndex = false);
    }
  }

  void _parseMagnetLink() {
    final magnet = _magnetController.text.trim();
    if (!magnet.startsWith('magnet:?')) {
      _showSnackbar("Invalid Magnet Link", isError: true);
      return;
    }
    try {
      final hashMatch = RegExp(r'xt=urn:btih:([a-zA-Z0-9]+)').firstMatch(magnet);
      final nameMatch = RegExp(r'dn=([^&]*)').firstMatch(magnet);
      if (hashMatch != null) setState(() => _hashController.text = hashMatch.group(1)!.toLowerCase());
      if (nameMatch != null) setState(() => _titleController.text = Uri.decodeComponent(nameMatch.group(1)!.replaceAll('+', ' ')));
      _showSnackbar("Metadata extracted!");
    } catch (e) {
      _showSnackbar("Parse failed", isError: true);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF00FF87),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BITNEXUS"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF00FF87)),
            onPressed: () => setState(() => _selectedIndex = 3),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildBrowseTab(),
          _buildDownloadsTab(),
          _buildUploadTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 80,
        backgroundColor: const Color(0xFF16161E),
        indicatorColor: const Color(0xFF00FF87).withOpacity(0.2),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() => _selectedIndex = index);
          if (index == 1) refreshDownloads();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Active'),
          NavigationDestination(icon: Icon(Icons.cloud_upload_outlined), selectedIcon: Icon(Icons.cloud_upload), label: 'Upload'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Config'),
        ],
      ),
    );
  }

  Widget _buildBrowseTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: "Search Index...", prefixIcon: Icon(Icons.search, color: Colors.grey)),
                  onSubmitted: (_) => fetchIndexFeed(),
                ),
              ),
              const SizedBox(width: 10),
              Container(decoration: BoxDecoration(color: const Color(0xFF00FF87), borderRadius: BorderRadius.circular(12)),
                child: IconButton(icon: const Icon(Icons.refresh, color: Colors.black), onPressed: fetchIndexFeed),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoadingIndex
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF87)))
              : indexTorrents.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.inbox, size: 64, color: Colors.grey), SizedBox(height: 16), Text("No torrents found")]))
                  : FadeTransition(opacity: _animationController,
                      child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), itemCount: indexTorrents.length,
                        itemBuilder: (context, index) {
                          final item = indexTorrents[index];
                          return _TorrentCard(
                            item: item, 
                            onDownload: () => startSmartDownload(item['magnet_link'], item['title']),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDownloadsTab() {
    if (isLoadingDownloads) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00FF87)));
    }

    if (activeDownloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text("No active torrents in qBittorrent", style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text("Check Settings > qBittorrent Config", style: TextStyle(color: Colors.grey, fontSize: 12)), // Fixed grey600
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activeDownloads.length,
      itemBuilder: (context, index) {
        final t = activeDownloads[index];
        final double progress = (t['progress'] ?? 0).toDouble();
        final bool isComplete = progress >= 1.0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: const Color(0xFF16161E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isComplete ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
              child: Icon(isComplete ? Icons.check : Icons.arrow_downward, 
                color: isComplete ? Colors.green : Colors.blue),
            ),
            title: Text(t['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${_formatBytes(t['size'])} • ${t['state']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFF424242),
                  color: const Color(0xFF00FF87),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_browser, color: Color(0xFF00FF87)),
              tooltip: "Open in qBittorrent WebUI",
              onPressed: () {
                launchUrl(Uri.parse("${QBitManager.baseUrl}/#/downloads"));
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildUploadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Publish Release", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00FF87))),
        const SizedBox(height: 30),
        const Text("Quick Import (Optional)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _magnetController, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: const InputDecoration(hintText: "Paste magnet link..."))),
          const SizedBox(width: 10),
          ElevatedButton(onPressed: _parseMagnetLink, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F26)), child: const Text("Parse", style: TextStyle(color: Color(0xFF00FF87)))),
        ]),
        const Divider(height: 40, color: Colors.grey),
        TextField(controller: _titleController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Content Title")),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(flex: 2, child: TextField(controller: _hashController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Info Hash"))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _sizeController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Size"))),
        ]),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(value: _selectedCategory, dropdownColor: const Color(0xFF1F1F26), style: const TextStyle(color: Colors.white),
          items: ["Anime", "Movies", "Games", "Software", "Music", "Other"].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
          onChanged: (val) => setState(() => _selectedCategory = val!),
        ),
        const SizedBox(height: 40),
        SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: isLoadingIndex ? null : submitRelease, child: isLoadingIndex ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black)) : const Text("PUBLISH TO INDEX NODE"))),
      ]),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("System Configuration", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00FF87))),
        const SizedBox(height: 20),
        
        const Text("Index Node (Feed Source)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
        const SizedBox(height: 10),
        TextField(controller: _serverController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(prefixIcon: Icon(Icons.dns))),
        
        const SizedBox(height: 30),
        const Divider(color: Colors.grey), // Fixed grey800
        const SizedBox(height: 10),

        const Text("qBittorrent Daemon (Downloader)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
        const Text("Enable WebUI in qBittorrent Tools > Options > WebUI", style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 10),
        
        TextField(controller: _qbUrlController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "URL (e.g., http://localhost:8080)", prefixIcon: Icon(Icons.link))),
        const SizedBox(height: 10),
        TextField(controller: _qbUserController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person))),
        const SizedBox(height: 10),
        TextField(controller: _qbPassController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock))),
        
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
          await QBitManager.saveSettings(
            _qbUrlController.text,
            _qbUserController.text,
            _qbPassController.text
          );
          
          final success = await QBitManager.login();
          if (success) {
            _showSnackbar("Connected to qBittorrent!");
            refreshDownloads();
          } else {
            _showSnackbar("Connection Failed. Check URL/Creds.", isError: true);
          }
        }, child: const Text("SAVE & TEST CONNECTION"))),
      ]),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}

class _TorrentCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onDownload;

  const _TorrentCard({required this.item, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFF16161E), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: CircleAvatar(backgroundColor: const Color(0xFF00FF87).withOpacity(0.1), child: Icon(_getIconForCategory(item['category']), color: const Color(0xFF00FF87))),
        title: Text(item['title'] ?? 'Untitled', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Row(children: [
          Chip(label: Text(item['category'] ?? 'General', style: const TextStyle(fontSize: 10, color: Colors.black)), backgroundColor: const Color(0xFF00B8D4), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          const SizedBox(width: 8),
          Text(item['size'] ?? 'N/A', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        trailing: IconButton(icon: const Icon(Icons.play_arrow, color: Color(0xFF00FF87)), tooltip: "Stream/Download Sequentially", onPressed: onDownload),
      ),
    );
  }

  IconData _getIconForCategory(String? category) {
    switch (category?.toLowerCase()) {
      case 'anime': return Icons.animation;
      case 'movies': return Icons.movie;
      case 'games': return Icons.sports_esports;
      case 'software': return Icons.code;
      case 'music': return Icons.music_note;
      default: return Icons.folder_open;
    }
  }
}