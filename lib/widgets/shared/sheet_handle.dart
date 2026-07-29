import 'package:flutter/material.dart';

class SheetHandle extends StatelessWidget {
  final Color color;

  const SheetHandle({super.key, this.color = const Color(0xFFD6CDDD)});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 48,
        height: 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
