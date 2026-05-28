import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const BitNexusApp());

class BitNexusApp extends StatelessWidget {
  const BitNexusApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BitNexus Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF00FF87),
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        cardColor: const Color(0xFF16161A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00FF87), secondary: Color(0xFFFF9F43)),
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

class _MainWorkspaceHubState extends State<MainWorkspaceHub> {
  String currentServer = "http://127.0.0.1:5000";
  List torrents = [];
  bool isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  String _selectedCategory = "Anime";

  @override
  void initState() { super.initState(); _serverController.text = currentServer; fetchFeed(); }

  Future<void> fetchFeed() async {
    setState(() => isLoading = true);
    try {
      final query = _searchController.text.trim();
      final response = await http.get(Uri.parse("$currentServer/api/feed?q=$query")).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) setState(() => torrents = json.decode(response.body));
    } catch (_) { setState(() => torrents = []); }
    finally { setState(() => isLoading = false); }
  }

  Future<void> submitRelease() async {
    final title = _titleController.text.trim(), infoHash = _hashController.text.trim().toLowerCase(), size = _sizeController.text.trim().isEmpty ? "Unknown" : _sizeController.text.trim();
    if (title.isEmpty || infoHash.length != 40) return;
    final generatedMagnet = "magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}";
    try {
      final response = await http.post(Uri.parse("$currentServer/api/submit"), body: {"title": title, "info_hash": infoHash, "magnet_link": generatedMagnet, "category": _selectedCategory, "size": size});
      if (response.statusCode == 200) { _titleController.clear(); _hashController.clear(); _sizeController.clear(); fetchFeed(); }
    } catch (_) {}
  }

  void launchMagnet(String magnetLink) async {
    await Clipboard.setData(ClipboardData(text: magnetLink));
    final Uri uri = Uri.parse(magnetLink);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("BitNexus Workspace Hub", style: TextStyle(color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
          bottom: const TabBar(indicatorColor: Color(0xFF00FF87), tabs: [Tab(icon: Icon(Icons.grid_view), text: "Browse Feed"), Tab(icon: Icon(Icons.cloud_upload), text: "Publish Release"), Tab(icon: Icon(Icons.settings), text: "Node Settings")]),
        ),
        body: TabBarView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(children: [Row(children: [Expanded(child: TextField(controller: _searchController, decoration: const InputDecoration(hintText: "Search terms...", border: OutlineInputBorder()), onSubmitted: (_) => fetchFeed())), const SizedBox(width: 10), ElevatedButton(onPressed: fetchFeed, style: ElevatedButton.styleFrom(minimumSize: const Size(100, 55)), child: const Icon(Icons.refresh))]), const SizedBox(height: 15), Expanded(child: isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF87))) : torrents.isEmpty ? const Center(child: Text("No records found.", style: TextStyle(color: Colors.grey))) : ListView.builder(itemCount: torrents.length, itemBuilder: (context, index) { final item = torrents[index]; return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: ListTile(leading: Chip(label: Text(item['category'] ?? 'General')), title: Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("Size: ${item['size']}"), trailing: IconButton(icon: const Icon(Icons.bolt, color: Color(0xFFFF9F43)), onPressed: () => launchMagnet(item['magnet_link'] ?? '')))); }))]),
            ),
            SingleChildScrollView(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Publish Anonymous Content", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00FF87))), const SizedBox(height: 20), TextField(controller: _titleController, decoration: const InputDecoration(labelText: "Content Title", border: OutlineInputBorder())), const SizedBox(height: 15), TextField(controller: _hashController, decoration: const InputDecoration(labelText: "Raw Info-Hash", border: OutlineInputBorder())), const SizedBox(height: 15), TextField(controller: _sizeController, decoration: const InputDecoration(labelText: "Size", border: OutlineInputBorder())), const SizedBox(height: 15), DropdownButtonFormField<String>(value: _selectedCategory, decoration: const InputDecoration(border: OutlineInputBorder()), items: ["Anime", "Movies", "Games", "Software"].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(), onChanged: (val) => setState(() => _selectedCategory = val!)), const SizedBox(height: 25), ElevatedButton(onPressed: submitRelease, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 55)), child: const Text("Push Release to Node"))])),
            Padding(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Federated Connection Config", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 15), TextField(controller: _serverController, decoration: const InputDecoration(border: OutlineInputBorder())), const SizedBox(height: 20), ElevatedButton(onPressed: () { setState(() { currentServer = _serverController.text.trim().replaceAll(RegExp(r'/'), ''); }); fetchFeed(); }, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), child: const Text("Sync Node Settings"))])),
          ],
        ),
      ),
    );
  }
}