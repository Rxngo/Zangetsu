import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/player_controller.dart';

void main() {
  group('isStreamOpenFailure', () {
    test('recognises a failed stream open', () {
      expect(
        PlayerCubit.isStreamOpenFailure(
          'Failed to open https://cdn.test/video.mp4',
        ),
        isTrue,
      );
    });

    test('ignores shader and local-file failures', () {
      expect(
        PlayerCubit.isStreamOpenFailure('Failed to open shader.glsl'),
        isFalse,
      );
      expect(
        PlayerCubit.isStreamOpenFailure('Cannot open file /tmp/clip.mp4'),
        isFalse,
      );
    });

    test('ignores unrelated playback failures', () {
      expect(
        PlayerCubit.isStreamOpenFailure('transient HLS segment warning'),
        isFalse,
      );
    });
  });
}
