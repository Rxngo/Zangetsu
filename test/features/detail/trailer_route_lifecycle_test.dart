import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/detail/trailer_route_lifecycle.dart';

void main() {
  group('TrailerRouteLifecycle', () {
    test('reports one cover and one reopen transition', () {
      final lifecycle = TrailerRouteLifecycle();

      expect(lifecycle.cover(), isTrue);
      expect(lifecycle.cover(), isFalse);
      expect(lifecycle.isCovered, isTrue);
      expect(lifecycle.uncover(), isTrue);
      expect(lifecycle.uncover(), isFalse);
      expect(lifecycle.isCovered, isFalse);
    });

    test('does not create a player while the detail route is covered', () {
      final lifecycle = TrailerRouteLifecycle();
      lifecycle.cover();

      expect(lifecycle.canCreatePlayer, isFalse);

      lifecycle.uncover();
      expect(lifecycle.canCreatePlayer, isTrue);
    });

    test('does not permit widget updates after disposal begins', () {
      final lifecycle = TrailerRouteLifecycle();

      expect(lifecycle.canUpdateUi, isTrue);
      lifecycle.beginDispose();

      expect(lifecycle.canUpdateUi, isFalse);
      expect(lifecycle.canCreatePlayer, isFalse);
    });
  });
}
