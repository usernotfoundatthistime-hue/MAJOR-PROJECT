import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // REQUIRED FOR THE TIMER
import 'dart:ui'; // <--- REQUIRED FOR THE BLUR EFFECT

// This allows us to navigate from anywhere in the app
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

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

class InactivityWrapper extends StatefulWidget {
  final Widget child;
  const InactivityWrapper({super.key, required this.child});

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // SET TO 10 SECONDS FOR YOUR DEMO (Change to minutes: 15 for production)
    _timer = Timer(const Duration(seconds: 30), _lockApp);
  }

  void _userInteracted() {
    if (!_isLocked) {
      _startTimer();
    }
  }

  void _lockApp() {
    if (!_isLocked) {
      setState(() => _isLocked = true);
      globalNavigatorKey.currentState?.push(
        // MAGIC FIX: PageRouteBuilder allows us to make the new screen transparent!
        PageRouteBuilder(
          opaque: false, // <--- This lets the chat show through
          pageBuilder: (context, animation, secondaryAnimation) =>
              PinLockScreen(
                onUnlock: () {
                  setState(() => _isLocked = false);
                  _startTimer();
                },
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _userInteracted,
      onPanDown: (_) => _userInteracted(),
      child: widget.child,
    );
  }
}

class MyApp extends StatelessWidget {
  final String? savedUser; // Accept the saved user
  const MyApp({super.key, this.savedUser});

  @override
  Widget build(BuildContext context) {
    return InactivityWrapper(
      // <--- WRAPS THE WHOLE APP
      child: MaterialApp(
        navigatorKey: globalNavigatorKey, // <--- ADDS THE GLOBAL KEY
        debugShowCheckedModeBanner: false,
        title: 'SAFE Chat',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E293B),
            elevation: 0,
          ),
        ),
        home: savedUser != null
            ? ChatListScreen(currentUser: savedUser!)
            : const LoginScreen(),
      ),
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
      Uri.parse(
        "$httpBase/messages/${widget.currentUser}/${Uri.encodeComponent(otherUser)}",
      ),
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

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text("Create Group Chat"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Group Name (e.g., ProjectTeam)",
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (controller.text.trim().isEmpty) return;
                        setState(() => isLoading = true);

                        // Remove spaces for clean hashtags
                        String safeGroupName = controller.text
                            .trim()
                            .replaceAll(" ", "");

                        final response = await http.post(
                          Uri.parse("$httpBase/create_group"),
                          headers: {"Content-Type": "application/json"},
                          body: jsonEncode({
                            "group_name": safeGroupName,
                            "creator": widget.currentUser,
                          }),
                        );

                        if (response.statusCode == 200) {
                          fetchUsers(); // Refresh the chat list instantly
                          if (mounted) Navigator.pop(ctx);
                        } else {
                          setState(() => isLoading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Create",
                        style: TextStyle(color: Colors.white),
                      ),
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BlockchainLedgerScreen(),
              ),
            ),
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
            icon: const Icon(
              Icons.group_add,
              color: Colors.blueAccent,
            ), // Create Group
            tooltip: "Create Group",
            onPressed: _showCreateGroupDialog,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1), // Add Friend
            tooltip: "Add Friend",
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
                    ).then((_) => fetchUsers()),
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

      // MAGIC FIX: Accept the message if it's 1-on-1 OR if the group_name matches the current window!
      bool isForThisChat =
          newMessage['sender'] == widget.otherUser ||
          newMessage['sender'] == "SYSTEM" ||
          newMessage['group_name'] == widget.otherUser;

      if (isForThisChat) {
        if (mounted) {
          setState(() {
            messages.insert(0, {
              "text": E2EE.decryptText(newMessage['text']),
              "isMe": newMessage['sender'] == widget.currentUser,
              "isSystem": newMessage['sender'] == "SYSTEM",
              "isSpam": newMessage['spam'] ?? false,
              "time": newMessage['timestamp'],
              "senderName": newMessage['sender'], // Track who sent it
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
      Uri.parse(
        "$httpBase/messages/${widget.currentUser}/${Uri.encodeComponent(widget.otherUser)}",
      ),
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
                "senderName": msg["sender"], // Track who sent it
              },
            )
            .toList()
            .reversed
            .toList();
      });
    }
  }

  void _showAddMemberDialog() {
    final controller = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text("Add Member to ${widget.otherUser}"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Enter exact Username",
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (controller.text.trim().isEmpty) return;
                        setState(() => isLoading = true);

                        final response = await http.post(
                          Uri.parse("$httpBase/add_to_group"),
                          headers: {"Content-Type": "application/json"},
                          body: jsonEncode({
                            "group_name":
                                widget.otherUser, // e.g., "#ProjectTeam"
                            "contact": controller.text.trim(),
                          }),
                        );

                        if (response.statusCode == 200) {
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Member successfully added!"),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          setState(() => isLoading = false);
                          final error = jsonDecode(response.body)["detail"];
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Add", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGroupInfoDialog() async {
    final response = await http.get(
      Uri.parse(
        "$httpBase/group_members/${Uri.encodeComponent(widget.otherUser)}",
      ),
    );
    if (response.statusCode == 200) {
      List members = jsonDecode(response.body);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text("${widget.otherUser} Members"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: members.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(Icons.person, color: Colors.blueAccent),
                  title: Text(members[index]),
                  trailing: members[index] == widget.currentUser
                      ? const Text(
                          "(You)",
                          style: TextStyle(color: Colors.green),
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Close",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () async {
                // Exit Group API Call
                await http.post(
                  Uri.parse("$httpBase/exit_group"),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "group_name": widget.otherUser,
                    "username": widget.currentUser,
                  }),
                );
                if (!mounted) return;
                Navigator.pop(ctx); // Close Dialog
                Navigator.pop(context); // Exit Chat Screen back to Home
              },
              child: const Text(
                "Exit Group",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
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
      appBar: AppBar(
        title: Text(widget.otherUser),
        actions: [
          // Magic Check: If the chat name starts with '#', it's a group!
          if (widget.otherUser.startsWith("#")) ...[
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blueAccent),
              tooltip: "Add Member",
              onPressed: _showAddMemberDialog,
            ),
            // THIS IS THE NEW INFO BUTTON
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white70),
              tooltip: "Group Info",
              onPressed: _showGroupInfoDialog,
            ),
          ],
        ],
      ),
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
                      // THIS IS THE NEW SENDER NAME TEXT
                      if (widget.otherUser.startsWith("#") &&
                          !msg["isMe"] &&
                          !msg["isSystem"])
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            msg["senderName"] ?? "Unknown",
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

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
        title: const Text("Security Ledger", style: TextStyle(fontSize: 18)),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: fetchBlockchain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Ledger is empty."));
          }

          // Reverse the chain so the newest block loads at the bottom
          final chain = snapshot.data!.reversed.toList();

          return ListView.builder(
            reverse: true, // Auto-scrolls to the newest block!
            padding: const EdgeInsets.all(16),
            itemCount: chain.length,
            itemBuilder: (context, index) {
              final block = chain[index];

              // Determine Threat Type and Colors from your Python backend
              String eventType = block['event_type'] ?? "UNKNOWN";
              bool isPhishing = eventType.toUpperCase() == "PHISHING";
              bool isSpam = eventType.toUpperCase() == "SPAM";
              bool isGenesis = eventType.toUpperCase() == "GENESIS_BLOCK";

              Color badgeColor = isPhishing
                  ? Colors.redAccent
                  : (isSpam ? Colors.orangeAccent : Colors.greenAccent);
              String icon = isPhishing ? "🎣" : (isSpam ? "🗑️" : "✅");
              String label = isPhishing
                  ? "PHISHING ATTEMPT"
                  : (isSpam ? "SPAM DETECTED" : "SYSTEM EVENT");

              Map<String, dynamic> dataPayload = {};
              try {
                dataPayload = block['data'] is String
                    ? jsonDecode(block['data'])
                    : block['data'];
              } catch (e) {}

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "🧱 Block #${block['index']}",
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            block['timestamp'].toString().split('.')[0],
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // The beautiful warning badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: badgeColor),
                        ),
                        child: Text(
                          "$icon $label",
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // The intercepted data
                      if (!isGenesis && dataPayload.isNotEmpty) ...[
                        Text(
                          "User: ${dataPayload['username'] ?? 'Unknown'}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "\"${dataPayload['message'] ?? ''}\"",
                          style: const TextStyle(
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else ...[
                        const Text(
                          "System Initialization",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],

                      const Divider(color: Colors.white24, height: 24),

                      // Muted Hashes (Keeps professors happy, keeps UI clean!)
                      Text(
                        "Hash: ${block['hash']}",
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        "Prev: ${block['previous_hash']}",
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
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

class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  const PinLockScreen({super.key, required this.onUnlock});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  String _errorMessage = "";
  bool _isLoading = false;

  void _verifyPin() async {
    if (_pinController.text.length != 4) {
      setState(() => _errorMessage = "Please enter all 4 digits.");
      return;
    }

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final currentUser = prefs.getString('loggedInUser');
    final savedPin = prefs.getString('mpin_$currentUser') ?? "1234";

    if (_pinController.text == savedPin) {
      if (!mounted) return;
      Navigator.pop(context);
      widget.onUnlock();
    } else {
      setState(() {
        _errorMessage = "Incorrect PIN. Session locked.";
        _pinController.clear();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(
          0.5,
        ), // Semi-transparent black
        body: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10.0,
            sigmaY: 10.0,
          ), // The heavy blur effect!
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_clock,
                    size: 80,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "SESSION TIMEOUT",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "For your security, SAFE Chat has been locked due to inactivity. Enter your MPIN to resume.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 40),

                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 16,
                      color: Colors.blueAccent,
                    ),
                    decoration: InputDecoration(
                      counterText: "",
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.5),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // The explicit UNLOCK button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyPin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "UNLOCK",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MpinSetupScreen extends StatefulWidget {
  final String username;
  const MpinSetupScreen({super.key, required this.username});

  @override
  State<MpinSetupScreen> createState() => _MpinSetupScreenState();
}

class _MpinSetupScreenState extends State<MpinSetupScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String _errorMessage = "";
  bool _isLoading = false;

  void _savePin() async {
    if (_pinController.text.length != 4 ||
        _confirmController.text.length != 4) {
      setState(() => _errorMessage = "PIN must be exactly 4 digits.");
      return;
    }

    if (_pinController.text != _confirmController.text) {
      setState(() {
        _errorMessage = "PINs do not match. Try again.";
        _confirmController.clear();
      });
      return;
    }

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mpin_${widget.username}', _pinController.text);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatListScreen(currentUser: widget.username),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.greenAccent),
              const SizedBox(height: 24),
              const Text(
                "SETUP SECURE MPIN",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Create a 4-digit PIN to secure your active sessions.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 40),

              _buildPinField(_pinController, "Enter 4-Digit PIN"),
              const SizedBox(height: 16),
              _buildPinField(_confirmController, "Confirm 4-Digit PIN"),

              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _savePin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          "SAVE MPIN",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 24,
        letterSpacing: 16,
        color: Colors.white,
      ),
      decoration: InputDecoration(
        counterText: "",
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 14,
          letterSpacing: 1,
          color: Colors.white38,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
    );
  }
}
