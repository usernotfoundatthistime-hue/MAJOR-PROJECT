import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'register_screen.dart';
import 'main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  String message = "";

  Future<void> loginUser() async {
    setState(() => _isLoading = true);
    // Note: 'localhost' works for Web, use '10.0.2.2' for Android Emulator
    final url = Uri.parse("$httpBase/login");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": usernameController.text,
          "password": passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["message"] == "Login successful") {
        setState(() => message = "Access Granted ✅");
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('loggedInUser', usernameController.text);

        // --- NEW LOGIC: Check if they have an MPIN ---
        final existingMpin = prefs.getString('mpin_${usernameController.text}');

        Future.delayed(const Duration(milliseconds: 500), () {
          if (existingMpin == null) {
            // No MPIN? Send them to Setup!
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    MpinSetupScreen(username: usernameController.text),
              ),
            );
          } else {
            // Already have an MPIN? Go straight to Chats!
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ChatListScreen(currentUser: usernameController.text),
              ),
            );
          }
        });
      } else {
        setState(() => message = data["error"] ?? "Invalid Credentials ❌");
      }
    } catch (e) {
      setState(() => message = "Connection Error ⚠️");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate Blue
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 400,
            ), // Prevents stretching
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon for "SAFE" vibe
                const Icon(
                  Icons.lock_person_rounded,
                  size: 80,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  "SAFE CHAT",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  "Secure Messaging Portal",
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 40),

                // Username Field
                _buildTextField(
                  controller: usernameController,
                  hint: "Username",
                  icon: Icons.alternate_email_rounded,
                ),
                const SizedBox(height: 20),

                // Password Field
                _buildTextField(
                  controller: passwordController,
                  hint: "Password",
                  icon: Icons.key_rounded,
                  isPassword: true,
                ),

                const SizedBox(height: 30),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : loginUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "LOGIN",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
                Text(
                  message,
                  style: TextStyle(
                    color: message.contains('✅')
                        ? Colors.green
                        : Colors.redAccent,
                  ),
                ),

                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterScreen(),
                    ),
                  ),
                  child: const Text(
                    "Don't have an account? Sign Up",
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
        ),
      ),
    );
  }
}
