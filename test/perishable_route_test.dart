import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:cus_yard_management/core/router.dart';

/// The route exists and resolves.
///
/// "no routes for location: /perishable-goods" came from a build made before
/// the route was added -- GoRouter builds its route table once, so a new route
/// needs a rebuild, not a hot restart. This pins that the table itself is
/// right, so the same report can be told apart from a stale binary next time.
void main() {
  test('/perishable-goods is a route GoRouter knows', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    final match = router.configuration.findMatch('/perishable-goods');
    expect(match.routes, isNotEmpty,
        reason: 'the nav item would land on Page Not Found');
    expect(match.uri.path, '/perishable-goods');
  });

  test('it sits alongside the other goods pages, not nested under one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    for (final path in const [
      '/perishable-goods',
      '/detained-packages',
      '/other-packages',
    ]) {
      final match = router.configuration.findMatch(path);
      expect(match.routes, isNotEmpty, reason: '$path does not resolve');
    }
  });
}
