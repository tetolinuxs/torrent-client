import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

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
        primaryColor: const Color(0xFF00FF87), // Neon Green
        scaffoldBackgroundColor: const Color(0xFF0A0A0C), // Deep Dark
        cardColor: const Color(0xFF16161E), // Card Dark
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF87),
          secondary: Color(0xFF00B8D4), // Cyan accent
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
          hintStyle: const TextStyle(color: Colors.grey), // Fixed
        ),
      ),
      home: const MainWorkspaceHub(),
    );
  }
}

class MainWorkspaceHub extends StatefulWidget {
  const MainWorkspaceHub({super.key});

  @override
  State<MainWorkspaceHub> createState() => _MainWorkspaceHubState();
}

class _MainWorkspaceHubState extends State<MainWorkspaceHub> with SingleTickerProviderStateMixin {
  String currentServer = "http://127.0.0.1:5000";
  List<dynamic> torrents = [];
  bool isLoading = false;
  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _serverController = TextEditingController(text: "http://127.0.0.1:5000");
  
  // Upload Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _magnetController = TextEditingController();
  String _selectedCategory = "Anime";

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    fetchFeed();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> fetchFeed() async {
    setState(() => isLoading = true);
    try {
      final query = _searchController.text.trim();
      final response = await http.get(
        Uri.parse("$currentServer/api/feed?q=$query"),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          torrents = json.decode(response.body);
          isLoading = false;
        });
        _animationController.forward(from: 0.0);
      } else {
        throw Exception('Failed to load');
      }
    } catch (_) {
      setState(() {
        torrents = [];
        isLoading = false;
      });
      _showSnackbar("Error connecting to node", isError: true);
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

  // Parse Magnet Link to extract InfoHash and Name
  void _parseMagnetLink() {
    final magnet = _magnetController.text.trim();
    if (!magnet.startsWith('magnet:?')) {
      _showSnackbar("Invalid Magnet Link", isError: true);
      return;
    }

    try {
      // Extract Info Hash (xt=urn:btih:HASH)
      final hashMatch = RegExp(r'xt=urn:btih:([a-zA-Z0-9]+)').firstMatch(magnet);
      // Extract Display Name (dn=NAME)
      final nameMatch = RegExp(r'dn=([^&]*)').firstMatch(magnet);

      if (hashMatch != null) {
        setState(() {
          _hashController.text = hashMatch.group(1)!.toLowerCase();
        });
      }
      
      if (nameMatch != null) {
        final encodedName = nameMatch.group(1)!;
        setState(() {
          _titleController.text = Uri.decodeComponent(encodedName.replaceAll('+', ' '));
        });
      }
      
      _showSnackbar("Metadata extracted from Magnet!");
    } catch (e) {
      _showSnackbar("Could not parse magnet link", isError: true);
    }
  }

  Future<void> submitRelease() async {
    final title = _titleController.text.trim();
    final infoHash = _hashController.text.trim().toLowerCase();
    final size = _sizeController.text.trim().isEmpty ? "Unknown" : _sizeController.text.trim();

    if (title.isEmpty || infoHash.length != 40) {
      _showSnackbar("Title and valid 40-char Hash required", isError: true);
      return;
    }

    final generatedMagnet = "magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}";

    setState(() => isLoading = true);

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
        _showSnackbar("Release Published Successfully!");
        // Switch to browse tab to see it
        setState(() => _selectedIndex = 0);
        fetchFeed();
      } else {
        _showSnackbar("Server Error: ${response.statusCode}", isError: true);
      }
    } catch (_) {
      _showSnackbar("Network Error", isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void launchMagnet(String magnetLink) async {
    await Clipboard.setData(ClipboardData(text: magnetLink));
    final Uri uri = Uri.parse(magnetLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      _showSnackbar("Magnet copied & launched");
    } else {
      _showSnackbar("No torrent client found", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BITNEXUS"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF00FF87)),
            onPressed: () => setState(() => _selectedIndex = 2),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildBrowseTab(),
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
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Node',
          ),
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
                  decoration: const InputDecoration(
                    hintText: "Search torrents...",
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                  ),
                  onSubmitted: (_) => fetchFeed(),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF87),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.black),
                  onPressed: fetchFeed,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF87)))
              : torrents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.inbox, size: 64, color: Colors.grey), // Fixed
                          SizedBox(height: 16),
                          Text("No torrents found", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : FadeTransition(
                      opacity: _animationController,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: torrents.length,
                        itemBuilder: (context, index) {
                          final item = torrents[index];
                          return _TorrentCard(item: item, onTap: () => launchMagnet(item['magnet_link'] ?? ''));
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildUploadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Publish Release",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00FF87)),
          ),
          const SizedBox(height: 8),
          const Text(
            "Share content with the federated network.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 30),

          // Magnet Parser Input
          const Text("Quick Import (Optional)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _magnetController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: "Paste magnet link to auto-fill...",
                    prefixIcon: Icon(Icons.link, color: Colors.grey, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _parseMagnetLink,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F26)),
                child: const Text("Parse", style: TextStyle(color: Color(0xFF00FF87))),
              ),
            ],
          ),
          const Divider(height: 40, color: Colors.grey), // Fixed
          
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: "Content Title", prefixIcon: Icon(Icons.title)),
          ),
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _hashController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: "Info Hash (40 chars)", prefixIcon: Icon(Icons.fingerprint)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _sizeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: "Size", prefixIcon: Icon(Icons.storage)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          DropdownButtonFormField<String>(
            value: _selectedCategory,
            dropdownColor: const Color(0xFF1F1F26),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.category)),
            items: ["Anime", "Movies", "Games", "Software", "Music", "Other"]
                .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                .toList(),
            onChanged: (val) => setState(() => _selectedCategory = val!),
          ),
          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: isLoading ? null : submitRelease,
              child: isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                : const Text("PUBLISH TO NODE"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Node Configuration",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00FF87)),
          ),
          const SizedBox(height: 30),
          const Text("Federated Server URL", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _serverController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.dns)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  currentServer = _serverController.text.trim().replaceAll(RegExp(r'/$'), '');
                });
                _showSnackbar("Node Updated. Refreshing feed...");
                fetchFeed();
              },
              child: const Text("CONNECT TO NODE"),
            ),
          ),
          const Spacer(),
          const Center(
            child: Text(
              "BitNexus Client v1.0.0\nFederated Protocol",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12), // Fixed
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Card Widget for Torrent Items
class _TorrentCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _TorrentCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)), // Fixed
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF00FF87).withOpacity(0.1),
          child: Icon(
            _getIconForCategory(item['category']),
            color: const Color(0xFF00FF87),
          ),
        ),
        title: Text(
          item['title'] ?? 'Untitled',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Row(
          children: [
            Chip(
              label: Text(item['category'] ?? 'General', style: const TextStyle(fontSize: 10, color: Colors.black)),
              backgroundColor: const Color(0xFF00B8D4),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Text(item['size'] ?? 'N/A', style: const TextStyle(color: Colors.grey, fontSize: 12)), // Fixed
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download_for_offline, color: Color(0xFF00FF87)),
          onPressed: onTap,
        ),
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