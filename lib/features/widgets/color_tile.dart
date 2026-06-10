import 'package:flutter/material.dart';

class ColorTile extends StatelessWidget {
  final String label;
  final int color;

  const ColorTile({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFCDD6F4),
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Color(0xFF000000 | color),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF2C2D32)),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '#${color.toRadixString(16).toUpperCase().padLeft(6, '0')}',
          style: const TextStyle(
            color: Color(0xFF6C7086),
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}
