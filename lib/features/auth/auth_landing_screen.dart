import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets/typewriter_text.dart';
import 'widgets/auth_widgets.dart';

enum _Step { landing, email, signIn, signUp }

const _taglines = [
  'Capture everything. Forget nothing.',
  'Your screenshots, beautifully organized.',
  'Visual memory, perfectly recalled.',
];
const _landingCtaHeight = 54.0;

class AuthLandingScreen extends StatefulWidget {
  const AuthLandingScreen({super.key});

  @override
  State<AuthLandingScreen> createState() => _AuthLandingScreenState();
}

class _AuthLandingScreenState extends State<AuthLandingScreen> {
  _Step _step = _Step.landing;
  bool _landingVisible = false;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _googleFallback = false;

  @override
  void initState() {
    super.initState();
    // Delay content appearance slightly so logo "settles" from splash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _landingVisible = true);
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
            const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.bgOverlay,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        elevation: 0,
      ),
    );
  }

  Future<void> _checkEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showError('Please enter a valid email address.');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await AuthService.checkEmailExists(email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = result == EmailCheckResult.notFound ? _Step.signUp : _Step.signIn;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _step = _Step.signIn; });
    }
  }

  Future<void> _signIn() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      _showError('Please enter your password.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: password,
      );
      // GoRouter redirect handles navigation on AuthAuthenticated
    } on Exception catch (e) {
      final m = e.toString().toLowerCase();
      final isCredential = m.contains('invalid') || m.contains('credentials');
      if (isCredential && mounted) setState(() => _googleFallback = true);
      _showError(_signInError(e, showGoogleHint: isCredential));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (password.length < 8) {
      _showError('Password must be at least 8 characters.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.signUp(
        email: _emailCtrl.text.trim(),
        password: password,
      );
      // GoRouter redirect handles navigation on AuthUnverified
    } on Exception catch (e) {
      _showError(_signUpError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await AuthService.signInWithGoogle();
    } on Exception catch (_) {
      _showError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  String _signInError(Object e, {bool showGoogleHint = false}) {
    final m = e.toString().toLowerCase();
    if (m.contains('invalid') || m.contains('credentials')) {
      return showGoogleHint
          ? 'Wrong password — or this account uses Google sign-in.'
          : 'Incorrect password. Try "Forgot password?" if needed.';
    }
    if (m.contains('not confirmed')) return 'Please verify your email first.';
    if (m.contains('rate limit')) return 'Too many attempts. Wait a moment.';
    if (m.contains('network') || m.contains('connection')) {
      return 'Network error. Check your connection.';
    }
    return 'Sign-in failed. Please try again.';
  }

  String _signUpError(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('already') || m.contains('registered')) {
      return 'An account with this email already exists.';
    }
    if (m.contains('weak')) return 'Password is too weak. Try a stronger one.';
    if (m.contains('rate limit')) return 'Too many attempts. Wait a moment.';
    return 'Sign-up failed. Please try again.';
  }

  void _back() {
    setState(() {
      if (_step == _Step.signIn || _step == _Step.signUp) {
        _step = _Step.email;
        _passwordCtrl.clear();
        _confirmCtrl.clear();
        _googleFallback = false;
      } else if (_step == _Step.email) {
        _step = _Step.landing;
        _emailCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.landing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            ),
            child: switch (_step) {
              _Step.landing => _LandingScene(
                  key: const ValueKey(_Step.landing),
                  contentVisible: _landingVisible,
                  googleLoading: _googleLoading,
                  onEmail: () => setState(() => _step = _Step.email),
                  onGoogle: _continueWithGoogle,
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
                  googleLoading: _googleLoading,
                  googleFallback: _googleFallback,
                  onBack: _back,
                  onSignIn: _signIn,
                  onGoogle: _continueWithGoogle,
                  onForgotPassword: () => context.push('/auth/forgot-password'),
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
    );
  }
}

// ── Landing ────────────────────────────────────────────────────────────────────

class _LandingScene extends StatelessWidget {
  final bool contentVisible;
  final bool googleLoading;
  final VoidCallback onEmail;
  final VoidCallback onGoogle;

  const _LandingScene({
    super.key,
    required this.contentVisible,
    required this.googleLoading,
    required this.onEmail,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: RepaintBoundary(child: _LandingOrbBackground()),
        ),
        _LandingView(
          contentVisible: contentVisible,
          googleLoading: googleLoading,
          onEmail: onEmail,
          onGoogle: onGoogle,
        ),
      ],
    );
  }
}

class _LandingView extends StatelessWidget {
  final bool contentVisible;
  final bool googleLoading;
  final VoidCallback onEmail;
  final VoidCallback onGoogle;

  const _LandingView({
    super.key,
    required this.contentVisible,
    required this.googleLoading,
    required this.onEmail,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 3),
        // Logo — rendered at the same position as Android splash icon
        // so the transition from native splash looks seamless.
        SvgPicture.asset(
          'assets/images/RecallOS-appicon.svg',
          width: 72,
          height: 72,
        ),
        const SizedBox(height: 16),
        AnimatedOpacity(
          opacity: contentVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          child: Column(
            children: [
              Text(
                'RecallOS',
                style: AppTypography.displayLg,
              ),
              const SizedBox(height: 14),
              TypewriterText(lines: _taglines),
            ],
          ),
        ),
        const Spacer(flex: 4),
        AnimatedOpacity(
          opacity: contentVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                AuthPrimaryButton(
                  label: 'Continue with Email',
                  onPressed: onEmail,
                ),
                const SizedBox(height: 12),
                AuthGoogleButton(
                  onPressed: onGoogle,
                  loading: googleLoading,
                  height: _landingCtaHeight,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _LandingOrbBackground extends StatefulWidget {
  const _LandingOrbBackground();

  @override
  State<_LandingOrbBackground> createState() => _LandingOrbBackgroundState();
}

class _LandingOrbBackgroundState extends State<_LandingOrbBackground>
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
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(color: AppColors.bgBase),
                _OrbLayer(
                  diameter: width * 1.1,
                  offset: Offset(
                    -width * 0.26 + width * 0.10 * t,
                    -height * 0.18 + height * 0.08 * (1 - t),
                  ),
                  colors: [
                    AppColors.accent.withValues(alpha: 0.34),
                    AppColors.accent.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
                _OrbLayer(
                  diameter: width * 0.95,
                  offset: Offset(
                    width * 0.48 - width * 0.09 * t,
                    height * 0.06 + height * 0.08 * t,
                  ),
                  colors: [
                    AppColors.accentText.withValues(alpha: 0.26),
                    AppColors.accentMuted.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
                _OrbLayer(
                  diameter: width * 0.84,
                  offset: Offset(
                    width * 0.10 + width * 0.08 * (1 - t),
                    height * 0.62 - height * 0.09 * t,
                  ),
                  colors: [
                    AppColors.accent.withValues(alpha: 0.18),
                    AppColors.accentMuted.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.14,
                    child: CustomPaint(
                      painter: _NoisePainter(
                        blockSize: 4,
                        dotColor: AppColors.borderSubtle.withValues(alpha: 0.60),
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
                          AppColors.bgBase.withValues(alpha: 0.44),
                          AppColors.bgBase.withValues(alpha: 0.84),
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
                          AppColors.bgBase.withValues(alpha: 0.18),
                          Colors.transparent,
                          AppColors.bgBase.withValues(alpha: 0.34),
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

  const _NoisePainter({
    required this.blockSize,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    final cols = (size.width / blockSize).ceil();
    final rows = (size.height / blockSize).ceil();

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final hash = ((x * 92837111) ^ (y * 689287499) ^ 0x5bd1e995) & 255;
        if (hash < 22) {
          final px = x * blockSize;
          final py = y * blockSize;
          canvas.drawRect(Rect.fromLTWH(px, py, 1.1, 1.1), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) {
    return oldDelegate.blockSize != blockSize || oldDelegate.dotColor != dotColor;
  }
}

// ── Email entry ────────────────────────────────────────────────────────────────

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
          Text("What's your email?", style: AppTypography.displayMd),
          const SizedBox(height: 8),
          Text(
            "We'll check if you have an account.",
            style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 36),
          AuthTextField(
            controller: controller,
            label: 'Email address',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onEditingComplete: onContinue,
            autofocus: true,
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: 'Continue',
            onPressed: onContinue,
            loading: loading,
          ),
        ],
      ),
    );
  }
}

// ── Sign in ────────────────────────────────────────────────────────────────────

class _SignInView extends StatelessWidget {
  final String email;
  final TextEditingController controller;
  final bool loading;
  final bool googleLoading;
  final bool googleFallback;
  final VoidCallback onBack;
  final VoidCallback onSignIn;
  final VoidCallback onGoogle;
  final VoidCallback onForgotPassword;

  const _SignInView({
    super.key,
    required this.email,
    required this.controller,
    required this.loading,
    required this.googleLoading,
    required this.googleFallback,
    required this.onBack,
    required this.onSignIn,
    required this.onGoogle,
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
          Text('Welcome back', style: AppTypography.displayMd),
          const SizedBox(height: 6),
          Text(
            email,
            style: AppTypography.bodyMd.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 36),
          AuthTextField(
            controller: controller,
            label: 'Password',
            hint: '••••••••',
            obscure: true,
            textInputAction: TextInputAction.done,
            onEditingComplete: onSignIn,
            autofocus: true,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onForgotPassword,
              child: Text(
                'Forgot password?',
                style: AppTypography.labelMd.copyWith(color: AppColors.accentText),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: 'Sign in',
            onPressed: onSignIn,
            loading: loading,
          ),
          if (googleFallback) ...[
            const SizedBox(height: 20),
            const AuthDivider(),
            const SizedBox(height: 20),
            AuthGoogleButton(
              onPressed: onGoogle,
              loading: googleLoading,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sign up ────────────────────────────────────────────────────────────────────

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
          Text('Create your account', style: AppTypography.displayMd),
          const SizedBox(height: 6),
          Text(
            email,
            style: AppTypography.bodyMd.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 36),
          AuthTextField(
            controller: passwordCtrl,
            label: 'Password',
            hint: 'At least 8 characters',
            obscure: true,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: confirmCtrl,
            label: 'Confirm password',
            hint: '••••••••',
            obscure: true,
            textInputAction: TextInputAction.done,
            onEditingComplete: onSignUp,
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: 'Create account',
            onPressed: onSignUp,
            loading: loading,
          ),
        ],
      ),
    );
  }
}

// ── Back button ────────────────────────────────────────────────────────────────

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
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          size: 17,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
