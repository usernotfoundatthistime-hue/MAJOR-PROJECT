import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:shared_preferences/shared_preferences.dart';

//----------Local connection test----------
//const String serverIp = "192.168.1.127";
//const String httpBase = "http://$serverIp:8000";
//const String wsBase = "ws://$serverIp:8000";

//----------Render server----------
const String httpBase = "https://safechat-api.onrender.com";
const String wsBase = "wss://safechat-api.onrender.com";

void main() async {
  // Ensure Flutter is ready before checking memory
  WidgetsFlutterBinding.ensureInitialized();

  // Check if a user is already saved
  final prefs = await SharedPreferences.getInstance();
  final savedUser = prefs.getString('loggedInUser');

  runApp(MyApp(savedUser: savedUser));
}

class MyApp extends StatelessWidget {
  final String? savedUser; // Accept the saved user
  const MyApp({super.key, this.savedUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SAFE Chat',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
        ),
      ),
      // If a user exists, go straight to chats. If not, show Login!
      home: savedUser != null
          ? ChatListScreen(currentUser: savedUser!)
          : const LoginScreen(),
    );
  }
}

class ChatListScreen extends StatefulWidget {
  final String currentUser;
  const ChatListScreen({super.key, required this.currentUser});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<String> users = [];
  Map<String, Map<String, dynamic>> chatPreviews = {};

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    // 1. Fetch from the new specific contacts route
    final response = await http.get(
      Uri.parse("$httpBase/contacts/${widget.currentUser}"),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      List<String> myContacts = data.cast<String>().toList();
      if (mounted) setState(() => users = myContacts);
      for (String contact in myContacts) {
        await fetchLastMessage(contact);
      }
    }
  }

  Future<void> fetchLastMessage(String otherUser) async {
    final response = await http.get(
      Uri.parse("$httpBase/messages/${widget.currentUser}/$otherUser"),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      if (mounted) {
        setState(() {
          chatPreviews[otherUser] = data.isNotEmpty
              ? {
                  "text": E2EE.decryptText(data.last["text"]),
                  "sender": data.last["sender"],
                }
              : {"text": "Tap to start chat", "sender": ""};
        });
      }
    }
  }

  void _showAddContactDialog() {
    final controller = TextEditingController();
    String errorMessage = ""; // Track the error text
    bool isLoading = false; // Track loading state for the button

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // Allows the dialog to update its own state
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text("Add Friend"),
            content: Column(
              mainAxisSize: MainAxisSize.min, // Wrap content tightly
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: "Enter exact Username",
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                  onChanged: (value) {
                    // Clear the error message as soon as they start typing again
                    if (errorMessage.isNotEmpty) {
                      setState(() => errorMessage = "");
                    }
                  },
                ),
                // Only show the error text if there is an error
                if (errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (controller.text.trim().isEmpty) return;

                        // Start loading and clear old errors
                        setState(() {
                          isLoading = true;
                          errorMessage = "";
                        });

                        final response = await http.post(
                          Uri.parse("$httpBase/add_contact"),
                          headers: {"Content-Type": "application/json"},
                          body: jsonEncode({
                            "owner": widget.currentUser,
                            "contact": controller.text.trim(),
                          }),
                        );

                        if (response.statusCode == 200) {
                          fetchUsers();
                          if (mounted) Navigator.pop(ctx); // Close on success
                        } else {
                          // Stop loading and show the error INSIDE the box
                          setState(() {
                            isLoading = false;
                            errorMessage = jsonDecode(response.body)["detail"];
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Add"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "SAFE Chat",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.security, color: Colors.greenAccent),
            tooltip: "View Blockchain Ledger",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlockchainLedgerScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white70),
            tooltip: "View Identity",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ProfileScreen(username: widget.currentUser),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _showAddContactDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: "Logout",
            onPressed: () {
              // Show the Confirmation Dialog
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orangeAccent,
                      ),
                      SizedBox(width: 10),
                      Text("Confirm Logout"),
                    ],
                  ),
                  content: const Text(
                    "Are you sure you want to log out of SAFE Chat?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(ctx), // Just close the dialog
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx); // Close the dialog first

                        // Clear the memory
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('loggedInUser');

                        // Navigate back to Login
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        }
                      },
                      child: const Text("Logout"),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: users.isEmpty
          ? const Center(child: Text("No contacts yet. Add one!"))
          : ListView.builder(
              padding: const EdgeInsets.only(top: 10),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final name = users[index];
                final preview = chatPreviews[name];
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blueAccent.withOpacity(0.2),
                      child: Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.blueAccent),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      preview?["text"] ?? "...",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          currentUser: widget.currentUser,
                          otherUser: name,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class E2EE {
  static final key = encrypt.Key.fromUtf8('MyFinalProjectSecretKey123456789');

  // FIXED: Using a static IV so decryption works consistently
  static final iv = encrypt.IV.fromUtf8('MySecureIV123456');

  static final encrypter = encrypt.Encrypter(encrypt.AES(key));

  static String encryptText(String plainText) {
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  static String decryptText(String encryptedText) {
    try {
      return encrypter.decrypt64(encryptedText, iv: iv);
    } catch (e) {
      return encryptedText;
    }
  }
}

class ChatScreen extends StatefulWidget {
  final String currentUser;
  final String otherUser;
  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> messages = [];
  late WebSocketChannel channel;

  @override
  void initState() {
    super.initState();
    fetchMessages();

    channel = WebSocketChannel.connect(
      Uri.parse('$wsBase/ws/${widget.currentUser}'),
    );

    channel.stream.listen((data) {
      final newMessage = jsonDecode(data);
      if (newMessage['sender'] == widget.otherUser ||
          newMessage['sender'] == "SYSTEM") {
        if (mounted) {
          setState(() {
            messages.insert(0, {
              "text": E2EE.decryptText(newMessage['text']),
              "isMe": newMessage['sender'] == widget.currentUser,
              "isSystem": newMessage['sender'] == "SYSTEM",
              "isSpam": newMessage['spam'] ?? false,
              "time": newMessage['timestamp'],
            });
          });
        }
      }
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    _controller.dispose();
    super.dispose();
  }

  Future<void> fetchMessages() async {
    final response = await http.get(
      Uri.parse("$httpBase/messages/${widget.currentUser}/${widget.otherUser}"),
    );
    if (response.statusCode == 200 && mounted) {
      final List data = jsonDecode(response.body);
      setState(() {
        messages = data
            .map(
              (msg) => {
                "text": E2EE.decryptText(msg["text"]),
                "isMe": msg["sender"] == widget.currentUser,
                "isSystem": msg["sender"] == "SYSTEM",
                "isSpam": msg["spam"] ?? false,
                "time": msg["timestamp"],
              },
            )
            .toList()
            .reversed
            .toList();
      });
    }
  }

  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final encryptedText = E2EE.encryptText(text);

    final response = await http.post(
      Uri.parse("$httpBase/send_message"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "sender": widget.currentUser,
        "receiver": widget.otherUser,
        "text": encryptedText, // ENCRYPTED payload for the DB
        "scan_text": text, // NEW: PLAIN text payload just for the AI
      }),
    );

    if (response.statusCode == 200) {
      _controller.clear();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      final data = jsonDecode(response.body);
      if (data["warning"] != null) {
        _showSecurityAlert("Spam Warning", data["warning"], Colors.orange);
      }
      fetchMessages();
    } else if (response.statusCode == 403) {
      _showSecurityAlert(
        "Message Blocked",
        "Suspicious/Phishing link detected.",
        Colors.redAccent,
      );
      fetchMessages();
    }
  }

  void _showSecurityAlert(String title, String message, Color color) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Icon(Icons.gpp_maybe, color: color),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherUser)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final String time = msg["time"] ?? "";
                return Align(
                  alignment: msg["isSystem"]
                      ? Alignment.center
                      : (msg["isMe"]
                            ? Alignment.centerRight
                            : Alignment.centerLeft),
                  child: Column(
                    crossAxisAlignment: msg["isMe"]
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        decoration: BoxDecoration(
                          color: msg["isMe"]
                              ? Colors.blueAccent
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              msg["text"],
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (msg["isSpam"] && !msg["isMe"])
                        const Text(
                          " ⚠ High-risk link. Open at your own risk.",
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: "Type a secure message...",
                border: InputBorder.none,
              ),
              onSubmitted: (_) => sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Colors.blueAccent),
            onPressed: sendMessage,
          ),
        ],
      ),
    );
  }
}

class BlockchainLedgerScreen extends StatelessWidget {
  const BlockchainLedgerScreen({super.key});

  Future<List<dynamic>> fetchBlockchain() async {
    final response = await http.get(Uri.parse("$httpBase/blockchain"));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["chain"];
    } else {
      throw Exception("Failed to load blockchain");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Security Ledger (Blockchain)",
          style: TextStyle(fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: fetchBlockchain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Ledger is empty."));
          }

          final chain = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chain.length,
            itemBuilder: (context, index) {
              final block = chain[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Block #${block['index'] ?? index}",
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          block['timestamp'] ?? "Unknown Time",
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    const Text(
                      "HASH:",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      block['hash'] ?? "N/A",
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.greenAccent,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "PREVIOUS HASH:",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      block['previous_hash'] ?? "N/A",
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "DATA:",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        block['data'] != null
                            ? jsonEncode(block['data'])
                            : "Genesis Block",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.orangeAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final String username;
  const ProfileScreen({super.key, required this.username});

  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await http.get(Uri.parse("$httpBase/profile/$username"));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to load profile");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digital Identity")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: fetchProfile(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.security, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  data['username'].toString().toUpperCase(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data['status'],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "CRYPTOGRAPHIC HASH",
                    style: TextStyle(
                      color: Colors.white54,
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blueAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    data['identity_hash'],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.blueAccent,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
