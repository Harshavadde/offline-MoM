import 'package:flutter/material.dart';

import 'tinted_icon.dart';

/// A single labelled metadata row (Card + ListTile + tinted leading icon +
/// trailing value), used to build the "Overview" tab on Meeting and
/// Document details screens (Batch 3, Design System Consolidation) -
/// both screens rendered this exact shape independently.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: TintedIcon(icon),
        title: Text(label),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
