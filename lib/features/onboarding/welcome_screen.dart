import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';

/// One page of the first-run introduction.
class WelcomePage {
  const WelcomePage({
    required this.icon,
    required this.title,
    required this.body,
    this.showMark = false,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Shows Trek's app icon (the T-mark on its gradient) in place of [icon].
  final bool showMark;
}

/// The pages [WelcomeScreen] walks through, in order.
const welcomePages = [
  WelcomePage(
    icon: Icons.flight_takeoff,
    title: 'Your trips. Your plan.',
    body:
        'Trek keeps everything about a trip in one place — where you\'re '
        'going, where you\'re staying, and what you\'ve booked.',
    showMark: true,
  ),
  WelcomePage(
    icon: Icons.view_timeline_outlined,
    title: 'Plan day by day',
    body:
        'Collect places worth visiting, then arrange them into a day-by-day '
        'itinerary alongside your accommodations, reservations, and notes.',
  ),
  WelcomePage(
    icon: Icons.group_outlined,
    title: 'Plan together',
    body:
        'Invite travel companions to the same trip to share the itinerary, '
        'split the budget, and work through packing lists and todos.',
  ),
  WelcomePage(
    icon: Icons.dns_outlined,
    title: 'Your server, your data',
    body:
        'Trek is self-hosted: next, you\'ll connect to your own Trek server '
        'and log in with your existing account. The app is built to keep '
        'working when your connection drops.',
  ),
];

/// First-run introduction shown before server setup on a fresh install
/// (see `buildAppRouter`). Finishing or skipping it records that it's been
/// seen via [OnboardingStorage] and continues to `/server-setup`. Entirely
/// local — no network access.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pageController = PageController();
  int _page = 0;

  bool get _isLastPage => _page == welcomePages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingStorageProvider).markWelcomeSeen();
    if (mounted) context.go('/server-setup');
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Visibility(
                  visible: !_isLastPage,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: welcomePages.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) =>
                    _WelcomePageView(page: welcomePages[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < welcomePages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLastPage ? _finish : _next,
                  child: Text(_isLastPage ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePageView extends StatelessWidget {
  const _WelcomePageView({required this.page});

  final WelcomePage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (page.showMark)
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/icon/icon.png', width: 96, height: 96),
            )
          else
            Icon(page.icon, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.xl),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
