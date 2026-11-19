import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';

/// "Pin it on the map": a small map preview of the chosen place (or a button when there is none).
/// Tapping opens the full-screen picker.
class PinField extends StatelessWidget {
  const PinField({super.key, required this.value, required this.onChanged});

  final LatLng? value;
  final ValueChanged<LatLng> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: value)),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (value == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: AlignmentDirectional.centerStart),
        onPressed: () => _pick(context),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr('map.add_pin')),
          Text(context.tr('map.pin_helps'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.check_circle, color: AlasColors.primary, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(context.tr('map.pinned'), style: t.textTheme.titleSmall)),
        TextButton(onPressed: () => _pick(context), child: Text(context.tr('map.change_pin'))),
      ]),
      const SizedBox(height: 6),
      DeliveryMap(destination: value, height: 150, onTap: () => _pick(context)),
    ]);
  }
}
