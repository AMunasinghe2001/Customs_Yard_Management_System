import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Detect network/timeout errors
    final errorStr = error.toString().toLowerCase();
    final isNetworkError = errorStr.contains('socketexception') ||
                          errorStr.contains('timeout') ||
                          errorStr.contains('host') ||
                          errorStr.contains('connection') ||
                          error is SocketException;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Diagram/Illustration
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isNetworkError ? context.colors.warningAmber : context.colors.dangerRed).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isNetworkError ? Iconsax.wifi_square : Iconsax.danger,
                size: 64,
                color: isNetworkError ? context.colors.warningAmber : context.colors.dangerRed,
              ),
            ),
            const Gap(24),
            Text(
              isNetworkError ? 'Network Connection Issue' : 'Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Gap(12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                isNetworkError
                    ? 'The request timed out while communicating with the server. Please check your internet connection or VPN and try again.'
                    : 'An unexpected error occurred: ${error.toString().split(':').last.trim()}',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.5),
              ),
            ),
            if (onRetry != null) ...[
              const Gap(32),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Iconsax.refresh, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryGold,
                  foregroundColor: context.colors.primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  elevation: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
