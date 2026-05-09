import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kStorageKey = 'onboarding_complete';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  static Future<bool> isComplete() async {
    const s = FlutterSecureStorage();
    return await s.read(key: _kStorageKey) == 'true';
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _cards = [
    _CardData(
      icon: Icons.handshake_outlined,
      iconColor: Color(0xFF00A86B),
      title: 'Welcome to EMI Locker',
      body:
          'The all-in-one platform for your device financing business. '
          'Track agreements, monitor devices, and stay connected with '
          'every customer — from one screen.',
    ),
    _CardData(
      icon: Icons.shield_outlined,
      iconColor: Color(0xFF3B82F6),
      title: 'Smart Device Oversight',
      body:
          'Devices enrolled in a financing agreement include a protection '
          'feature that keeps customers on track with their payment plan. '
          'Customers are informed of this during the enrollment process.',
    ),
    _CardData(
      icon: Icons.lock_outline,
      iconColor: Color(0xFF8B5CF6),
      title: 'Your Data Is Safe',
      body:
          'All customer and business data is encrypted in transit and at '
          'rest. We never sell or share data with third parties. '
          'You are in full control.',
    ),
  ];

  Future<void> _agree() async {
    const FlutterSecureStorage().write(key: _kStorageKey, value: 'true');
    widget.onComplete();
  }

  void _next() {
    _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _cards.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _OnboardingCard(data: _cards[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  _DotIndicator(count: _cards.length, current: _page),
                  const SizedBox(height: 20),
                  if (_page < _cards.length - 1)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _next,
                        child: const Text('Next'),
                      ),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _agree,
                        child: const Text('I Agree & Get Started'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'By tapping this button, you confirm you have read and understood the above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.data});
  final _CardData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: data.iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 48, color: data.iconColor),
          ),
          const SizedBox(height: 32),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D1117),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00A86B) : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _CardData {
  const _CardData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
}
