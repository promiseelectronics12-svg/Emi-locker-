import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

// Theming constants for the Light Pill aesthetic
const Color kEmeraldGreen = Color(0xFF10b981);
const Color kEmeraldDark = Color(0xFF064e3b);
const Color kLightBg = Color(0xFFf9fafb);
const Color kSoftBorder = Color(0xFFe5e7eb);
const Color kTextPrimary = Color(0xFF111827);

class UIPlaygroundScreen extends StatelessWidget {
  const UIPlaygroundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'EMI Locker UI Playground',
          style: GoogleFonts.manrope(
            color: kTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interactive Components',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
                letterSpacing: -0.5,
              ),
            ).animate().fade(duration: 400.ms).slideY(begin: 0.2, end: 0),

            const SizedBox(height: 8),
            Text(
                  'Tap, hold, and focus on these elements to feel the Rive-inspired physics and flutter_animate micro-interactions.',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                )
                .animate()
                .fade(delay: 200.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0),

            const SizedBox(height: 32),

            // 1. Pill Button
            _SectionHeader(title: 'Primary Pill Button'),
            const SizedBox(height: 16),
            Center(
                  child: PillButton(
                    label: 'Sign In Securely',
                    onPressed: () {
                      // Simulate action
                    },
                  ),
                )
                .animate()
                .fade(delay: 400.ms)
                .scale(begin: const Offset(0.9, 0.9)),

            const SizedBox(height: 32),

            // 2. Rounded Input Field
            _SectionHeader(title: 'Rounded Input Field'),
            const SizedBox(height: 16),
            RoundedInputField(
              hintText: 'Enter your email',
              icon: Icons.email_outlined,
            ).animate().fade(delay: 500.ms).slideX(begin: 0.1),

            const SizedBox(height: 16),
            RoundedInputField(
              hintText: 'Password',
              icon: Icons.lock_outline,
              isPassword: true,
            ).animate().fade(delay: 600.ms).slideX(begin: 0.1),

            const SizedBox(height: 32),

            // 3. Stat Card
            _SectionHeader(title: 'Interactive Stat Card'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'Total Devices',
                    value: '1,429',
                    icon: Icons.smartphone,
                    color: kEmeraldGreen,
                  ),
                ).animate().fade(delay: 700.ms).scale(),
                const SizedBox(width: 16),
                Expanded(
                  child: StatCard(
                    title: 'Locked',
                    value: '38',
                    icon: Icons.lock,
                    color: Colors.redAccent,
                  ),
                ).animate().fade(delay: 800.ms).scale(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: kEmeraldDark,
        letterSpacing: 1.0,
      ),
    );
  }
}

// ==========================================
// INTERACTIVE COMPONENTS
// ==========================================

/// A fully rounded pill button with scale-down physics on press
class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const PillButton({super.key, required this.label, required this.onPressed});

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) =>
          Transform.scale(scale: _scaleAnimation.value, child: child),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: kEmeraldGreen,
          borderRadius: BorderRadius.circular(100), // Max radius for pill shape
          boxShadow: [
            BoxShadow(
              color: kEmeraldGreen.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            splashColor: Colors.white.withValues(alpha: 0.2),
            highlightColor: Colors.transparent,
            onHighlightChanged: (isHighlighted) {
              if (isHighlighted) {
                _controller.forward();
              } else {
                _controller.reverse();
              }
            },
            onTap: widget.onPressed,
            child: Center(
              child: Text(
                widget.label,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A highly rounded input field that animates border color on focus
class RoundedInputField extends StatefulWidget {
  final String hintText;
  final IconData icon;
  final bool isPassword;
  final TextEditingController? controller;

  const RoundedInputField({
    super.key,
    required this.hintText,
    required this.icon,
    this.isPassword = false,
    this.controller,
  });

  @override
  State<RoundedInputField> createState() => _RoundedInputFieldState();
}

class _RoundedInputFieldState extends State<RoundedInputField> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      height: 60,
      decoration: BoxDecoration(
        color: _isFocused ? Colors.white : kLightBg,
        borderRadius: BorderRadius.circular(100), // Max radius
        border: Border.all(
          color: _isFocused ? kEmeraldGreen : kSoftBorder,
          width: _isFocused ? 2 : 1,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: kEmeraldGreen.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Center(
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          obscureText: widget.isPassword,
          style: GoogleFonts.manrope(color: kTextPrimary, fontSize: 16),
          decoration: InputDecoration(
            border: InputBorder.none,
            prefixIcon: Icon(
              widget.icon,
              color: _isFocused ? kEmeraldGreen : Colors.grey[400],
            ),
            hintText: widget.hintText,
            hintStyle: GoogleFonts.manrope(
              color: Colors.grey[400],
              fontSize: 16,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// An interactive stat card that elevates slightly on hover/press
class StatCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) => setState(() => _isHovered = false),
        onTapCancel: () => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(
              24,
            ), // High radius, almost pill but blocky enough for cards
            border: Border.all(color: kSoftBorder.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _isHovered ? 0.15 : 0.05),
                blurRadius: _isHovered ? 16 : 8,
                offset: Offset(0, _isHovered ? 8 : 4),
              ),
            ],
          ),
          transform: Matrix4.translationValues(
            0,
            _isHovered ? -4 : 0,
            0,
          ), // Slight lift effect
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(height: 16),
              Text(
                widget.value,
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.title,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
