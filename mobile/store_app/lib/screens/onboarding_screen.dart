import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/onboarding_art.dart';
import 'shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  Future<void> _finish() async {
    await context.read<AppSettings>().prefs.setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final settings = context.watch<AppSettings>();
    final last = _index == 2;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              const LeafLogo(size: 36),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('brand.full'), style: t.textTheme.titleSmall)),
              TextButton(onPressed: _finish, child: Text(context.tr('ob.skip'))),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: 3,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  switch (i) {
                    0 => IngredientsArt(active: _index == 0),
                    1 => DeliveryArt(active: _index == 1, cashLabel: context.tr('ob.cash')),
                    _ => OffersArt(active: _index == 2, couponLabel: context.tr('ob.coupon'), offerLabel: context.tr('ob.offer')),
                  },
                  const SizedBox(height: 36),
                  Text(context.tr('ob.${i + 1}.title'), style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(context.tr('ob.${i + 1}.body'),
                      style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index ? t.colorScheme.primary : t.colorScheme.outline,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
          ]),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              Text(context.tr('ob.choose_lang'), style: t.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {settings.lang},
                onSelectionChanged: (s) => settings.setLang(s.first),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last ? _finish : () => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                  child: Text(context.tr(last ? 'ob.start' : 'ob.next')),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
