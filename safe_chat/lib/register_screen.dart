import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_screen.dart';
import 'main.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String message = "";
  bool _isLoading = false;

  // Password validation states
  bool hasMinLength = false;
  bool hasUppercase = false;
  bool hasLowercase = false;
  bool hasNumber = false;
  bool hasSymbol = false;
  bool passwordsMatch = false;

  void checkPassword(String password) {
    setState(() {
      hasMinLength = password.length >= 8 && password.length <= 16;
      hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      hasLowercase = RegExp(r'[a-z]').hasMatch(password);
      hasNumber = RegExp(r'[0-9]').hasMatch(password);
      hasSymbol = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
      passwordsMatch = password == confirmPasswordController.text;
    });
  }

  void checkConfirmPassword(String confirmPassword) {
    setState(() {
      passwordsMatch = confirmPassword == passwordController.text;
    });
  }

  Future<void> register() async {
    if (!hasMinLength ||
        !hasUppercase ||
        !hasLowercase ||
        !hasNumber ||
        !hasSymbol ||
        !passwordsMatch) {
      setState(() => message = "Please meet all security requirements ⚠️");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$httpBase/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": usernameController.text,
          "password": passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => message = "Account Created! Redirecting... ✅");
        Future.delayed(
          const Duration(seconds: 1),
          () => Navigator.pop(context),
        );
      } else {
        setState(() => message = data["detail"] ?? "Registration failed ❌");
      }
    } catch (e) {
      setState(() => message = "Server connection error ⚠️");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                const Icon(
                  Icons.shield_rounded,
                  size: 60,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Create Account",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),

                _buildTextField(
                  usernameController,
                  "Username",
                  Icons.person_outline,
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  passwordController,
                  "Password",
                  Icons.lock_outline,
                  isPassword: true,
                  onChanged: checkPassword,
                ),

                // Password Requirements Grid
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniRule("8-16 Chars", hasMinLength),
                          ),
                          Expanded(
                            child: _buildMiniRule("Uppercase", hasUppercase),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniRule("Lowercase", hasLowercase),
                          ),
                          Expanded(child: _buildMiniRule("Number", hasNumber)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniRule(
                              r"Special Symbol (@#$)",
                              hasSymbol,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                _buildTextField(
                  confirmPasswordController,
                  "Confirm Password",
                  Icons.verified_user_outlined,
                  isPassword: true,
                  onChanged: checkConfirmPassword,
                ),

                // Password Match Indicator
                if (confirmPasswordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMiniRule(
                            passwordsMatch
                                ? "Passwords match"
                                : "Passwords do not match",
                            passwordsMatch,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "REGISTER",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: message.contains('✅')
                        ? Colors.green
                        : Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPassword = false,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent),
        ),
      ),
    );
  }

  Widget _buildMiniRule(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.circle_outlined,
            color: isValid ? Colors.green : Colors.white24,
            size: 14,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: isValid ? Colors.green : Colors.white38,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
