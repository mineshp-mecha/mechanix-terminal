import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    title: Text(
      label,
      style: const TextStyle(
        color: Color(0xFFCDD6F4),
        fontFamily: 'monospace',
        fontSize: 14,
      ),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF6C7086),
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: Color(0xFF6C7086), size: 18),
      ],
    ),
  );
}
