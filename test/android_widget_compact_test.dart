import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

void main() {
  test(
    'Static source regression (not placed-widget runtime): one-cell metadata and option routing',
    () {
      final info = _source('android/app/src/main/res/xml/itstheday_widget_info.xml');
      final provider = _source(
        'android/app/src/main/kotlin/com/himanusia/itstheday/ItsTheDayWidgetProvider.kt',
      );

      expect(info, contains('android:initialLayout="@layout/itstheday_widget_compact"'));
      expect(info, contains('android:minWidth="40dp"'));
      expect(info, contains('android:minHeight="40dp"'));
      expect(info, contains('android:minResizeWidth="40dp"'));
      expect(info, contains('android:minResizeHeight="40dp"'));
      expect(info, contains('android:targetCellWidth="1"'));
      expect(info, contains('android:targetCellHeight="1"'));
      expect(provider, contains('override fun onAppWidgetOptionsChanged'));
      expect(provider, contains('AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH'));
      expect(provider, contains('AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT'));
      expect(provider, contains('itstheday_widget_compact'));
      expect(provider, contains('R.layout.itstheday_widget'));
    },
  );

  test(
    'Static source regression (not placed-widget runtime): native numeric pace and deep link contract',
    () {
      final provider = _source(
        'android/app/src/main/kotlin/com/himanusia/itstheday/ItsTheDayWidgetProvider.kt',
      );
      final activity = _source(
        'android/app/src/main/kotlin/com/himanusia/itstheday/MainActivity.kt',
      );
      final gateway = _source('lib/platform/android_widget_gateway.dart');
      final full = _source('android/app/src/main/res/layout/itstheday_widget.xml');
      final compact = _source(
        'android/app/src/main/res/layout/itstheday_widget_compact.xml',
      );

      expect(gateway, contains("'goalCompleted': goal.completed"));
      expect(gateway, contains("'goalTarget': goal.goalTarget"));
      expect(gateway, contains("'goalUnit':"));
      expect(activity, contains('.putLong("goalCompleted"'));
      expect(activity, contains('.putLong("goalTarget"'));
      expect(activity, contains('.putString("goalUnit"'));
      expect(provider, contains('goalCompleted'));
      expect(provider, contains('goalTarget'));
      expect(provider, contains('goalUnit'));
      expect(provider, contains('remaining >= days'));
      expect(provider, contains('remaining / days'));
      expect(provider, contains('days / remaining'));
      expect(provider, contains('remaining <= 0L || days <= 0L'));
      expect(provider, contains('Math.floorDiv'));
      expect(provider, contains('putExtra("focusId"'));
      expect(provider, contains('putExtra("focusKind"'));
      expect(full, contains('widget_progress'));
      expect(full, contains('widget_pace'));
      expect(compact, contains('widget_compact_countdown'));
      expect(compact, contains('widget_compact_progress'));
      expect(compact, isNot(contains('widget_pace')));
    },
  );

  test(
    'Static source regression (not placed-widget runtime): constrained clock/spark mark and scoped raster generation',
    () {
      final foreground = _source(
        'android/app/src/main/res/drawable/itstheday_icon_foreground.xml',
      );
      final splash = _source(
        'android/app/src/main/res/drawable/itstheday_splash_mark.xml',
      );
      final generator = _source('tool/generate_icons.py');

      expect(foreground, contains('android:scaleX="0.78"'));
      expect(foreground, contains('M80,23'));
      expect(foreground, isNot(contains('M14,14')));
      expect(splash, contains('M80,23'));
      expect(generator, contains('--android-only'));
      expect(generator, contains('ANDROID_MARK_SCALE'));
    },
  );
}
