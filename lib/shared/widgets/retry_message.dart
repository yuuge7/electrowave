import 'package:flutter/material.dart';

class RetryMessage extends StatelessWidget {
  const RetryMessage({
    super.key,
    this.message = 'Your library could not be loaded.',
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.library_music_outlined, size: 40),
        const SizedBox(height: 12),
        Text(message),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    ),
  );
}
