import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Design tokens (mirrored from main app AppColors) ──────────────────────────
const _bgBase        = Color(0xFF0F0F0F);
const _bgElevated    = Color(0xFF1A1A1A);
const _bgSurface     = Color(0xFF141414);
const _accent        = Color(0xFF7C3AED);
const _accentHigh    = Color(0xFF8B52EF);
const _accentDeep    = Color(0xFF6D28D9);
const _accentText    = Color(0xFFA78BFA);
const _textPrimary   = Color(0xFFF7F7F7);
const _textSecondary = Color(0xFFA0A0A0);
const _textMuted     = Color(0xFF6B6B6B);
const _borderDefault = Color(0xFF2A2A2A);
const _borderWhite   = Color(0x1AFFFFFF);
const _error         = Color(0xFFE5484D);

enum _Step { landing, email, signIn, signUp }

class LoginScreen extends StatefulWidget {
  final String redirect;
  const LoginScreen({super.key, required this.redirect});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _Step _step = _Step.landing;
  bool _contentVisible = false;

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _loading       = false;
  bool _googleLoading = false;

  bool get _isStackContext => widget.redirect.contains('/stack/');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _contentVisible = true);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 15, color: _error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: _textPrimary, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF222222),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _error.withValues(alpha: 0.35)),
        ),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        elevation: 0,
      ),
    );
  }

  // Probes with a deliberately wrong password; the error message reveals
  // whether the account exists ("Invalid login credentials") or not ("User not
  // found" / "Email not found").
  Future<void> _checkEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showError('Please enter a valid email address.');
      return;
    }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: '____probe__recallos____',
      );
      if (mounted) context.go(widget.redirect);
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final accountExists =
          msg.contains('invalid') || msg.contains('credentials') || msg.contains('not confirmed');
      setState(() {
        _loading = false;
        _step = accountExists ? _Step.signIn : _Step.signUp;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _step = _Step.signIn; });
    }
  }

  Future<void> _signIn() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) { _showError('Please enter your password.'); return; }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: password,
      );
      if (mounted) context.go(widget.redirect);
    } on AuthException catch (e) {
      if (mounted) _showError(_signInErrorMsg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    final password = _passwordCtrl.text;
    if (password.length < 8) { _showError('Password must be at least 8 characters.'); return; }
    if (password != _confirmCtrl.text) { _showError('Passwords do not match.'); return; }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: password,
      );
      if (mounted) context.go(widget.redirect);
    } on AuthException catch (e) {
      if (mounted) _showError(_signUpErrorMsg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
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
      if (mounted) { _showError(e.message); setState(() => _googleLoading = false); }
    }
  }

  void _back() {
    setState(() {
      if (_step == _Step.signIn || _step == _Step.signUp) {
        _step = _Step.email;
        _passwordCtrl.clear();
        _confirmCtrl.clear();
      } else if (_step == _Step.email) {
        _step = _Step.landing;
        _emailCtrl.clear();
      }
    });
  }

  String _signInErrorMsg(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid') || m.contains('credentials')) return 'Wrong password. Try again or use Google sign-in.';
    if (m.contains('not confirmed')) return 'Please verify your email first.';
    if (m.contains('rate limit')) return 'Too many attempts. Wait a moment.';
    return 'Sign-in failed. Please try again.';
  }

  String _signUpErrorMsg(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('already') || m.contains('registered')) return 'An account with this email already exists.';
    if (m.contains('weak')) return 'Password is too weak. Try a stronger one.';
    if (m.contains('rate limit')) return 'Too many attempts. Wait a moment.';
    return 'Sign-up failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.landing,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _back(); },
      child: Scaffold(
        backgroundColor: _bgBase,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const IgnorePointer(child: RepaintBoundary(child: _OrbBackground())),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                      child: child,
                    ),
                    child: switch (_step) {
                      _Step.landing => _LandingView(
                          key: const ValueKey(_Step.landing),
                          contentVisible: _contentVisible,
                          googleLoading: _googleLoading,
                          isStackContext: _isStackContext,
                          onEmail: () => setState(() => _step = _Step.email),
                          onGoogle: _signInWithGoogle,
                        ),
                      _Step.email => _EmailView(
                          key: const ValueKey(_Step.email),
                          controller: _emailCtrl,
                          loading: _loading,
                          onBack: _back,
                          onContinue: _checkEmail,
                        ),
                      _Step.signIn => _SignInView(
                          key: const ValueKey(_Step.signIn),
                          email: _emailCtrl.text.trim(),
                          controller: _passwordCtrl,
                          loading: _loading,
                          onBack: _back,
                          onSignIn: _signIn,
                          onForgotPassword: () => _showError(
                            'Password reset is not yet available here. Please use the RecallOS app.',
                          ),
                        ),
                      _Step.signUp => _SignUpView(
                          key: const ValueKey(_Step.signUp),
                          email: _emailCtrl.text.trim(),
                          passwordCtrl: _passwordCtrl,
                          confirmCtrl: _confirmCtrl,
                          loading: _loading,
                          onBack: _back,
                          onSignUp: _signUp,
                        ),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Landing view ───────────────────────────────────────────────────────────────

class _LandingView extends StatelessWidget {
  final bool contentVisible;
  final bool googleLoading;
  final bool isStackContext;
  final VoidCallback onEmail;
  final VoidCallback onGoogle;

  const _LandingView({
    super.key,
    required this.contentVisible,
    required this.googleLoading,
    required this.isStackContext,
    required this.onEmail,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 3),
        const _AppIcon(),
        const SizedBox(height: 16),
        AnimatedOpacity(
          opacity: contentVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          child: const Column(
            children: [
              Text(
                'RecallOS',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Capture everything. Forget nothing.',
                style: TextStyle(color: _textMuted, fontSize: 15),
              ),
            ],
          ),
        ),
        const Spacer(flex: 2),
        AnimatedOpacity(
          opacity: contentVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: const _StackedCardsHero(),
        ),
        const Spacer(flex: 3),
        AnimatedOpacity(
          opacity: contentVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                if (isStackContext) ...[
                  const Text(
                    'Sign in to view this shared stack',
                    style: TextStyle(color: _textMuted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],
                _PrimaryButton(label: 'Continue with Email', onPressed: onEmail, height: 54),
                const SizedBox(height: 12),
                _GoogleButton(onPressed: onGoogle, loading: googleLoading),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Email view ─────────────────────────────────────────────────────────────────

class _EmailView extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _EmailView({
    super.key,
    required this.controller,
    required this.loading,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _BackButton(onTap: onBack),
          const SizedBox(height: 52),
          const Text(
            "What's your email?",
            style: TextStyle(
              color: _textPrimary, fontSize: 26,
              fontWeight: FontWeight.w700, letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We'll check if you have an account.",
            style: TextStyle(color: _textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 36),
          _AuthField(
            controller: controller,
            label: 'Email address',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onSubmitted: (_) => onContinue(),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Continue', onPressed: onContinue, loading: loading),
        ],
      ),
    );
  }
}

// ── Sign-in view ───────────────────────────────────────────────────────────────

class _SignInView extends StatelessWidget {
  final String email;
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onSignIn;
  final VoidCallback onForgotPassword;

  const _SignInView({
    super.key,
    required this.email,
    required this.controller,
    required this.loading,
    required this.onBack,
    required this.onSignIn,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _BackButton(onTap: onBack),
          const SizedBox(height: 52),
          const Text(
            'Welcome back',
            style: TextStyle(
              color: _textPrimary, fontSize: 26,
              fontWeight: FontWeight.w700, letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(email, style: const TextStyle(color: _textMuted, fontSize: 15)),
          const SizedBox(height: 36),
          _AuthField(
            controller: controller,
            label: 'Password',
            hint: '••••••••',
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => onSignIn(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onForgotPassword,
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  color: _accentText, fontSize: 13, fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Sign in', onPressed: onSignIn, loading: loading),
        ],
      ),
    );
  }
}

// ── Sign-up view ───────────────────────────────────────────────────────────────

class _SignUpView extends StatelessWidget {
  final String email;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onSignUp;

  const _SignUpView({
    super.key,
    required this.email,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.loading,
    required this.onBack,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _BackButton(onTap: onBack),
          const SizedBox(height: 52),
          const Text(
            'Create your account',
            style: TextStyle(
              color: _textPrimary, fontSize: 26,
              fontWeight: FontWeight.w700, letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(email, style: const TextStyle(color: _textMuted, fontSize: 15)),
          const SizedBox(height: 36),
          _AuthField(
            controller: passwordCtrl,
            label: 'Password',
            hint: 'At least 8 characters',
            obscure: true,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          _AuthField(
            controller: confirmCtrl,
            label: 'Confirm password',
            hint: '••••••••',
            obscure: true,
            onSubmitted: (_) => onSignUp(),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Create account', onPressed: onSignUp, loading: loading),
        ],
      ),
    );
  }
}

// ── Reusable components ────────────────────────────────────────────────────────

class _AppIcon extends StatelessWidget {
  const _AppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.layers_rounded, color: Colors.white, size: 34),
    );
  }
}

class _StackedCardsHero extends StatelessWidget {
  const _StackedCardsHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 224,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(-22, 10),
            child: Transform.rotate(
              angle: -0.14,
              child: _ScreenCard(
                width: 138,
                height: 184,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E1E1E), Color(0xFF161616)],
                ),
                borderColor: const Color(0xFF222222),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(20, 8),
            child: Transform.rotate(
              angle: 0.10,
              child: _ScreenCard(
                width: 140,
                height: 186,
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF1C1C1C), Color(0xFF151515)],
                ),
                borderColor: const Color(0xFF232323),
              ),
            ),
          ),
          _ScreenCard(
            width: 148,
            height: 194,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF242424), Color(0xFF181818)],
            ),
            borderColor: const Color(0xFF2E2E2E),
            showIcon: true,
          ),
        ],
      ),
    );
  }
}

class _ScreenCard extends StatelessWidget {
  final double width;
  final double height;
  final LinearGradient gradient;
  final Color borderColor;
  final bool showIcon;

  const _ScreenCard({
    required this.width,
    required this.height,
    required this.gradient,
    required this.borderColor,
    this.showIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: showIcon
          ? Center(
              child: Icon(
                Icons.layers_rounded,
                size: 32,
                color: _accent.withValues(alpha: 0.25),
              ),
            )
          : null,
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.height = 52,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  bool get _disabled => widget.onPressed == null || widget.loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: _disabled
          ? null
          : (_) { setState(() => _pressed = false); widget.onPressed?.call(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: Container(
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _disabled
                  ? const [Color(0x332D1B69), Color(0x332D1B69)]
                  : _pressed
                      ? const [_accentDeep, _accentDeep]
                      : const [_accentHigh, _accent],
              stops: const [0.0, 0.35],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _disabled ? const Color(0x332D1B69) : _accentDeep,
            ),
            boxShadow: _disabled
                ? null
                : const [BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: _disabled ? const Color(0xFF444444) : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const _GoogleButton({required this.onPressed, this.loading = false});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.loading ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.loading
          ? null
          : (_) { setState(() => _pressed = false); widget.onPressed?.call(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xFF1E1E1E) : _bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderWhite),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    valueColor: AlwaysStoppedAnimation(_textSecondary),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.network(
                      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                      width: 20,
                      height: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Continue with Google',
                      style: TextStyle(
                        color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  const _AuthField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscure;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          autofocus: widget.autofocus,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(color: _textPrimary, fontSize: 15),
          cursorColor: _accent,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: Color(0xFF444444), fontSize: 15),
            filled: true,
            fillColor: _bgElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _borderDefault),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent),
            ),
            suffixIcon: widget.obscure
                ? IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: _textMuted,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderDefault),
        ),
        child: const Icon(Icons.arrow_back_rounded, size: 17, color: _textSecondary),
      ),
    );
  }
}

// ── Animated orb background (ported from mobile AuthLandingScreen) ─────────────

class _OrbBackground extends StatefulWidget {
  const _OrbBackground();

  @override
  State<_OrbBackground> createState() => _OrbBackgroundState();
}

class _OrbBackgroundState extends State<_OrbBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(color: _bgBase),
                _OrbLayer(
                  diameter: w * 1.1,
                  offset: Offset(-w * 0.26 + w * 0.10 * t, -h * 0.18 + h * 0.08 * (1 - t)),
                  colors: [
                    _accent.withValues(alpha: 0.34),
                    _accent.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
                _OrbLayer(
                  diameter: w * 0.95,
                  offset: Offset(w * 0.48 - w * 0.09 * t, h * 0.06 + h * 0.08 * t),
                  colors: [
                    _accentText.withValues(alpha: 0.26),
                    const Color(0xFF2D1B69).withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
                _OrbLayer(
                  diameter: w * 0.84,
                  offset: Offset(w * 0.10 + w * 0.08 * (1 - t), h * 0.62 - h * 0.09 * t),
                  colors: [
                    _accent.withValues(alpha: 0.18),
                    const Color(0xFF2D1B69).withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.14,
                    child: CustomPaint(
                      painter: _NoisePainter(
                        blockSize: 4,
                        dotColor: const Color(0xFF222222).withValues(alpha: 0.60),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.18),
                        radius: 1.1,
                        colors: [
                          Colors.transparent,
                          _bgBase.withValues(alpha: 0.44),
                          _bgBase.withValues(alpha: 0.84),
                        ],
                        stops: const [0.35, 0.72, 1],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _bgBase.withValues(alpha: 0.18),
                          Colors.transparent,
                          _bgBase.withValues(alpha: 0.34),
                        ],
                        stops: const [0, 0.46, 1],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _OrbLayer extends StatelessWidget {
  final double diameter;
  final Offset offset;
  final List<Color> colors;

  const _OrbLayer({
    required this.diameter,
    required this.offset,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  final double blockSize;
  final Color dotColor;

  const _NoisePainter({required this.blockSize, required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    final cols = (size.width / blockSize).ceil();
    final rows = (size.height / blockSize).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final hash = ((x * 92837111) ^ (y * 689287499) ^ 0x5bd1e995) & 255;
        if (hash < 22) {
          canvas.drawRect(
            Rect.fromLTWH(x * blockSize.toDouble(), y * blockSize.toDouble(), 1.1, 1.1),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) =>
      old.blockSize != blockSize || old.dotColor != dotColor;
}
