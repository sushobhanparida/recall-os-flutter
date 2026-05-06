import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  final String redirect;
  const LoginScreen({super.key, required this.redirect});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    if (_isSignUp) {
      if (_confirmCtrl.text != password) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
      if (password.length < 6) {
        setState(() => _error = 'Password must be at least 6 characters.');
        return;
      }
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
      if (mounted) context.go(widget.redirect);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      const origin = String.fromEnvironment(
        'WEB_ORIGIN',
        defaultValue: 'https://recallos-web-viewer.vercel.app',
      );
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '$origin${widget.redirect}',
      );
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
      _confirmCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isSignUp ? 'Create a RecallOS account' : 'Sign in to RecallOS',
                  style: const TextStyle(
                    color: Color(0xFFF7F7F7),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _isSignUp
                      ? 'Create an account to view this shared stack.'
                      : 'Sign in to view this shared stack.',
                  style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Google button
                _OutlineButton(
                  onTap: _loading ? null : _signInWithGoogle,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                        width: 18,
                        height: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isSignUp ? 'Sign up with Google' : 'Continue with Google',
                        style: const TextStyle(
                            color: Color(0xFFF7F7F7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _Divider(),
                const SizedBox(height: 20),
                _Field(controller: _emailCtrl, hint: 'Email', obscure: false),
                const SizedBox(height: 12),
                _Field(controller: _passwordCtrl, hint: 'Password', obscure: true),
                if (_isSignUp) ...[
                  const SizedBox(height: 12),
                  _Field(
                    controller: _confirmCtrl,
                    hint: 'Confirm password',
                    obscure: true,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _loading ? null : _submitEmail,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white),
                          )
                        : Text(
                            _isSignUp ? 'Create account' : 'Sign in',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                // Toggle between sign-in and sign-up
                GestureDetector(
                  onTap: _loading ? null : _toggleMode,
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Sign up",
                    style: const TextStyle(
                      color: Color(0xFF7C3AED),
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _OutlineButton({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2A2A)),
          color: const Color(0xFF141414),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  const _Field({required this.controller, required this.hint, required this.obscure});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Color(0xFFF7F7F7), fontSize: 14),
      cursorColor: const Color(0xFF7C3AED),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555555)),
        filled: true,
        fillColor: const Color(0xFF141414),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF7C3AED)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: Color(0xFF555555), fontSize: 12)),
        ),
        const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
      ],
    );
  }
}
