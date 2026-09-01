import 'package:flutter/material.dart';

/// Centered progress spinner for a screen/section waiting on an async
/// operation (e.g. login submission). Screens should prefer this over an
/// unbounded inline `CircularProgressIndicator` so loading states look
/// consistent across the app.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
