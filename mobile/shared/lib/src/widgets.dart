import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'format.dart';
import 'l10n.dart';
import 'theme.dart';

/// The website's leaf logo (same path as public/favicon.svg).
class LeafLogo extends StatelessWidget {
  const LeafLogo({super.key, this.size = 40, this.background = AlasColors.logoGreen, this.foreground = AlasColors.cream});

  final double size;
  final Color background, foreground;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LeafPainter(background, foreground)),
      );
}

class _LeafPainter extends CustomPainter {
  _LeafPainter(this.bg, this.fg);

  final Color bg, fg;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(14 * s)),
      Paint()..color = bg,
    );
    // M17 41c9-2 16-9 18-23 9 6 14 16 10 25-4 9-17 10-24 4 7-2 13-7 17-15-5 5-11 9-21 9Z
    final p = Path()
      ..moveTo(17 * s, 41 * s)
      ..relativeCubicTo(9 * s, -2 * s, 16 * s, -9 * s, 18 * s, -23 * s)
      ..relativeCubicTo(9 * s, 6 * s, 14 * s, 16 * s, 10 * s, 25 * s)
      ..relativeCubicTo(-4 * s, 9 * s, -17 * s, 10 * s, -24 * s, 4 * s)
      ..relativeCubicTo(7 * s, -2 * s, 13 * s, -7 * s, 17 * s, -15 * s)
      ..relativeCubicTo(-5 * s, 5 * s, -11 * s, 9 * s, -21 * s, 9 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = fg);
  }

  @override
  bool shouldRepaint(_LeafPainter old) => old.bg != bg || old.fg != fg;
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.radius = 0, this.aspectRatio});

  final String? url;
  final BoxFit fit;
  final double radius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainer,
      alignment: Alignment.center,
      child: Icon(Icons.eco_outlined, color: scheme.onSurfaceVariant.withValues(alpha: .4), size: 32),
    );
    Widget child = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    if (aspectRatio != null) child = AspectRatio(aspectRatio: aspectRatio!, child: child);
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child) : child;
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? message, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: t.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 18),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return EmptyView(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? context.tr('app.offline') : context.trError(error),
      message: offline ? context.tr('app.offline_hint') : null,
      action: context.tr('app.retry'),
      onAction: onRetry,
    );
  }
}

/// Builds a widget from a Future with loading / error / retry handling.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    await f.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          return widget.builder(context, snap.data as T, _reload);
        },
      );
}

class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.price, this.discountPrice, this.large = false, this.prefix});

  final double? price, discountPrice;
  final bool large;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final onSale = discountPrice != null && price != null && discountPrice! < price!;
    final main = (large ? t.textTheme.titleLarge : t.textTheme.titleSmall)?.copyWith(
      color: onSale ? AlasColors.sale : t.colorScheme.primary,
      fontWeight: FontWeight.w700,
      fontFamily: 'packages/alas_shared/Manrope',
    );
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (prefix != null) Text(prefix!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        Text(money(onSale ? discountPrice : price), style: main),
        if (onSale)
          Text(
            money(price),
            style: t.textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: t.colorScheme.onSurfaceVariant,
              fontFamily: 'packages/alas_shared/Manrope',
            ),
          ),
      ],
    );
  }
}

/// "Shipped" / "Delivered" read "Ready for pickup" / "Picked up" for store-pickup orders.
String statusLabel(BuildContext context, String status, {bool pickup = false}) =>
    pickup && (status == 'shipped' || status == 'delivered') ? context.tr('status.${status}_pickup') : context.tr('status.$status');

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.pickup = false});

  final String status;
  final bool pickup;

  static Color color(String status) => switch (status) {
        'pending' => AlasColors.warning,
        'confirmed' => const Color(0xFF2B6CB0),
        'shipped' => const Color(0xFF6B46C1),
        'delivered' => AlasColors.primary,
        _ => AlasColors.destructive,
      };

  @override
  Widget build(BuildContext context) {
    final c = color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel(context, status, pickup: pickup),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AlasColors.destructive : null,
    ));
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String? confirm, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AlasColors.destructive) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm ?? ctx.tr('app.confirm')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Renders the tiny policy markup used on the server ('## ' heading, '- ' bullet).
class SimpleRichText extends StatelessWidget {
  const SimpleRichText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(line.substring(3), style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(line.substring(2), style: t.bodyMedium)),
          ]),
        ));
      } else {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line, style: t.bodyMedium)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}


/// MaterialApp.builder: keeps every screen above the phone's navigation buttons/gesture bar.
/// Android 15+ always draws apps edge to edge, so without this the bottom of lists and
/// buttons slides under the system bar.
Widget keepAboveSystemBar(BuildContext context, Widget? child) => ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox.shrink()),
    );
