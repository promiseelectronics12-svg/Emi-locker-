import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kStorageKey = 'onboarding_complete';

const _steps = [
  _WelcomeStep(
    title: 'Welcome to EMI Locker',
    body:
        'The all-in-one workspace for device financing. Track agreements, monitor enrolled phones, and stay connected with every customer.',
    label: 'Welcome',
    asset: 'assets/mascot/nestbot_pose_welcome.png',
    accent: Color(0xFF149B8A),
  ),
  _WelcomeStep(
    title: 'Activate With Confidence',
    body:
        'Generate the activation code, capture EMI terms, and bind the phone cleanly before customer handover.',
    label: 'Activation',
    asset: 'assets/mascot/nestbot_pose_code.png',
    accent: Color(0xFF2878CF),
  ),
  _WelcomeStep(
    title: 'Protected, Not Punished',
    body:
        'Keep protection fair and visible. Dealers stay in control while customers understand what is happening.',
    label: 'Protection',
    asset: 'assets/mascot/nestbot_pose_secure.png',
    accent: Color(0xFF2D64B3),
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  static Future<bool> isComplete() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: _kStorageKey) == 'true';
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _textCtrl = PageController();
  late final AnimationController _idleCtrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await const FlutterSecureStorage().write(key: _kStorageKey, value: 'true');
    if (!mounted) return;
    widget.onComplete();
  }

  void _goTo(int page) {
    if (page < 0 || page >= _steps.length) return;
    _textCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _advance() {
    if (_page == _steps.length - 1) {
      _finish();
      return;
    }
    _goTo(_page + 1);
  }

  void _back() => _goTo(_page - 1);

  @override
  Widget build(BuildContext context) {
    final current = _steps[_page];
    final isFirst = _page == 0;
    final isLast = _page == _steps.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 12, 0),
                    child: AnimatedOpacity(
                      opacity: isLast ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: TextButton(
                        onPressed: isLast ? null : _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF8B98A5),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: _MascotStage(
                    animation: _idleCtrl,
                    step: current,
                    height: compact ? 260 : 310,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: PageView.builder(
                    controller: _textCtrl,
                    itemCount: _steps.length,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemBuilder: (context, index) =>
                        _CopyPanel(step: _steps[index]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Dots(
                        count: _steps.length,
                        activeIndex: _page,
                        activeColor: current.accent,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          AnimatedOpacity(
                            opacity: isFirst ? 0.34 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: SizedBox(
                              width: 108,
                              height: 52,
                              child: OutlinedButton(
                                onPressed: isFirst ? null : _back,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: current.accent,
                                  side: BorderSide(
                                    color: current.accent.withValues(
                                      alpha: isFirst ? 0.18 : 0.42,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Back',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: current.accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _advance,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: Text(
                                    isLast
                                        ? 'I Agree & Get Started'
                                        : 'Continue',
                                    key: ValueKey(isLast),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AnimatedOpacity(
                        opacity: isLast ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Text(
                          'By tapping this button you confirm you have read and understood the above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.45,
                            color: Color(0xFF8B98A5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeStep {
  const _WelcomeStep({
    required this.title,
    required this.body,
    required this.label,
    required this.asset,
    required this.accent,
  });

  final String title;
  final String body;
  final String label;
  final String asset;
  final Color accent;
}

class _MascotStage extends StatelessWidget {
  const _MascotStage({
    required this.animation,
    required this.step,
    required this.height,
  });

  final Animation<double> animation;
  final _WelcomeStep step;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 292,
      height: height,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value * math.pi * 2;
          final breath = 0.992 + (math.sin(t) + 1) * 0.006;
          final floatY = math.sin(t + math.pi / 5) * 3.0;
          final shadowPulse = 0.11 + (math.sin(t) + 1) * 0.025;

          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 8,
                child: Container(
                  width: 190 + (math.sin(t).abs() * 14),
                  height: 30,
                  decoration: BoxDecoration(
                    color: step.accent.withValues(alpha: shadowPulse),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: step.accent.withValues(alpha: 0.10),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: step.accent.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    step.label,
                    style: TextStyle(
                      color: step.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, floatY),
                child: Transform.scale(
                  scale: breath,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            ],
          );
        },
        child: Image.asset(
          step.asset,
          height: height - 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _CopyPanel extends StatelessWidget {
  const _CopyPanel({required this.step});

  final _WelcomeStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.22,
              color: Color(0xFF0D1117),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.62,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.activeIndex,
    required this.activeColor,
  });

  final int count;
  final int activeIndex;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? activeColor : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
