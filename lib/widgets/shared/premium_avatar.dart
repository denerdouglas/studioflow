import 'dart:io';
import 'package:flutter/material.dart';

class PremiumAvatar extends StatelessWidget {
  final String? localPath;
  final String? remoteUrl;
  final String fallbackInitials;
  final double radius;
  final VoidCallback? onTap;

  const PremiumAvatar({
    super.key,
    this.localPath,
    this.remoteUrl,
    required this.fallbackInitials,
    this.radius = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;

    if (localPath != null && localPath!.isNotEmpty) {
      final file = File(localPath!);
      if (file.existsSync()) {
        imageProvider = FileImage(file);
      }
    } else if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      imageProvider = NetworkImage(remoteUrl!);
    }

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      backgroundImage: imageProvider,
      child: imageProvider == null
          ? Text(
              fallbackInitials,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: avatar,
      );
    }

    return avatar;
  }
}
