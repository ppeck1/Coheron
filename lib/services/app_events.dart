// lib/services/app_events.dart
// Lightweight refresh bus.
//
// This keeps Phase 1 screens responsive without introducing provider/state libs.

import 'package:flutter/foundation.dart';

class AppEvents {
  AppEvents._();

  /// Increment when a new Entry is saved (baseline/event/retro).
  static final ValueNotifier<int> entrySavedTick = ValueNotifier<int>(0);

  /// Increment when a Vital is saved.
  static final ValueNotifier<int> vitalSavedTick = ValueNotifier<int>(0);

  static void notifyEntrySaved() {
    entrySavedTick.value = entrySavedTick.value + 1;
  }

  static void notifyVitalSaved() {
    vitalSavedTick.value = vitalSavedTick.value + 1;
  }
}
