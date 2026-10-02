import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:its_the_day/presentation/brand_mark.dart';
import 'package:its_the_day/presentation/day_illustrations.dart';
import 'package:its_the_day/presentation/itstheday_theme.dart';

void main() {
  testWidgets('dark form inputs stay legible at 320dp with large text', (
    tester,
  ) async {
    final theme = itsthedayDarkTheme();
    final lightTheme = itsthedayLightTheme();
    expect(theme.inputDecorationTheme.fillColor, isNot(Colors.white));
    expect(
      theme.inputDecorationTheme.fillColor,
      theme.colorScheme.surfaceContainerHigh,
    );
    expect(lightTheme.inputDecorationTheme.fillColor, Colors.white);
    expect(theme.textSelectionTheme.cursorColor, theme.colorScheme.primary);
    expect(theme.textSelectionTheme.selectionColor, isNotNull);
    expect(
      theme.textSelectionTheme.selectionHandleColor,
      theme.colorScheme.primary,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Form(
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('dark-form-title'),
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'A useful title',
                        ),
                      ),
                      TextFormField(
                        key: const ValueKey('dark-form-email'),
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      TextFormField(
                        key: const ValueKey('dark-form-note'),
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          alignLabelWithHint: true,
                        ),
                      ),
                      InputDecorator(
                        key: const ValueKey('dark-form-decorator'),
                        decoration: const InputDecoration(
                          labelText: 'Server date',
                        ),
                        child: const Text('Assigned on submit'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final key in const [
      ValueKey('dark-form-title'),
      ValueKey('dark-form-email'),
      ValueKey('dark-form-note'),
    ]) {
      final decorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(
        decorator.decoration.fillColor,
        theme.inputDecorationTheme.fillColor,
      );
    }
    final serverDecorator = tester.widget<InputDecorator>(
      find.byKey(const ValueKey('dark-form-decorator')),
    );
    expect(
      serverDecorator.decoration
          .applyDefaults(theme.inputDecorationTheme)
          .fillColor,
      theme.inputDecorationTheme.fillColor,
    );

    final firstField = find.byKey(const ValueKey('dark-form-title'));
    await tester.tap(firstField);
    await tester.enterText(firstField, 'Readable');
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: firstField, matching: find.byType(EditableText)),
    );
    expect(editable.style.color, theme.textTheme.bodyLarge?.color);
    expect(editable.cursorColor, theme.textSelectionTheme.cursorColor);
    expect(editable.selectionColor, theme.textSelectionTheme.selectionColor);
  });

  testWidgets('original marks stay square inside rectangular constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: itsthedayDarkTheme(),
        home: Column(
          children: [
            SizedBox(
              width: 28,
              height: 52,
              child: ItsTheDayMark(
                key: const ValueKey('constrained-brand-mark'),
                size: 48,
              ),
            ),
            SizedBox(
              width: 28,
              height: 52,
              child: ClockSparkIllustration(
                key: const ValueKey('constrained-clock-spark'),
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final key in const [
      ValueKey('constrained-brand-mark'),
      ValueKey('constrained-clock-spark'),
    ]) {
      final size = tester
          .renderObject<RenderBox>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(CustomPaint),
            ),
          )
          .size;
      expect(size.width, size.height);
      expect(size.width, greaterThan(0));
    }
  });
}
