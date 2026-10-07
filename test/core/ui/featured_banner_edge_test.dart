import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/ui/featured_banner_edge.dart';

MediaItem _item(String id, String title) => MediaItem(
  id: id,
  title: title,
  url: 'https://example.test/$id',
  type: ProviderType.anime,
  sourceId: 'test',
);

void main() {
  testWidgets('places featured title content at the bottom', (tester) async {
    final item = _item('1', 'First Show');
    MediaItem? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedBannerEdge(items: [item], onInfo: (m) => opened = m),
        ),
      ),
    );

    final banner = tester.getRect(
      find.byKey(const ValueKey('featuredEdgeBanner')),
    );
    final content = find.byKey(const ValueKey('edgeBannerContent-1'));
    final viewButton = find.byKey(const ValueKey('edgeBannerViewButton'));
    expect(tester.widget<Align>(content).alignment, Alignment.bottomCenter);
    expect(banner.left, 0);
    expect(
      banner.right,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
    expect(find.text('First Show'), findsOneWidget);
    expect(find.text('View Details'), findsOneWidget);
    expect(tester.getCenter(viewButton).dx, closeTo(banner.center.dx, 1));
    expect(tester.getSize(viewButton).width, lessThanOrEqualTo(150));
    expect(tester.getSize(viewButton).height, lessThanOrEqualTo(48));
    expect(find.text('Play'), findsNothing);

    await tester.tap(viewButton);
    expect(opened, item);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('swiping changes the featured title', (tester) async {
    MediaItem? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedBannerEdge(
            items: [_item('1', 'First Show'), _item('2', 'Second Show')],
            onInfo: (m) => opened = m,
          ),
        ),
      ),
    );

    expect(find.text('First Show'), findsOneWidget);
    await tester.fling(
      find.byKey(const ValueKey('edgeBannerGesture')),
      const Offset(-300, 0),
      2000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Second Show'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edgeBannerViewButton')));
    expect(opened?.title, 'Second Show');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
