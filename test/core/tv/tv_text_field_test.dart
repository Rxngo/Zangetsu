import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/tv/tv_text_field.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    bool accessibleNavigation = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessibleNavigation),
        child: const MaterialApp(
          home: Scaffold(
            body: TvTextField(autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('TvTextField lands focus without opening the IME', (tester) async {
    await pumpField(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    // Editable (so OK focus-gain can raise leanback) but edit node is not
    // focused yet — nav focus owns the landing.
    expect(field.readOnly, isFalse);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('TvTextField shows the soft keyboard when tapped', (tester) async {
    await pumpField(tester);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'tap must raise the IME on the same text box',
    );
  });

  testWidgets('TvTextField shows the soft keyboard on Select/OK', (tester) async {
    await pumpField(tester);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'Select/OK must raise the IME on the same text box',
    );
  });

  testWidgets(
    'TvTextField shows the soft keyboard on Select when accessibleNavigation '
    'is true (Fire TV false positive)',
    (tester) async {
      await pumpField(tester, accessibleNavigation: true);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason:
            'Select must open the IME even when the TV falsely reports a '
            'screen reader',
      );
    },
  );

  testWidgets(
    'TvTextField Semantics.onTap opens the IME '
    '(TalkBack / directional activate)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await pumpField(tester, accessibleNavigation: true);

      final node = tester.getSemantics(find.byType(TextField));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'activate action must open the keyboard on the same field',
      );

      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);
      handle.dispose();
    },
  );
}
