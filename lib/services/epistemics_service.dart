// lib/services/epistemics_service.dart
//
// CR-COV/EP-v1: Default epistemics (q,c) derived from coverage when user has not provided overrides.
// This is a minimal substrate hook that is compatible with future DSCS expansion.
//
// Storage: RolePlaneEpistemics(date, role_id, plane_id, q_0_1, c_0_1, q_source, c_source, rule_id)

import '../database/database_helper.dart';
import '../canon/roles.dart';
import 'input_coverage_service.dart';
import '../canon/symbol_governance.dart';

class EpistemicsResult {
  final double q;
  final double c;
  final String qSource;
  final String cSource;

  const EpistemicsResult({
    required this.q,
    required this.c,
    required this.qSource,
    required this.cSource,
  });
}

class EpistemicsService {
  EpistemicsService({
    DatabaseHelper? db,
    InputCoverageService? coverageService,
  })  : _db = db ?? DatabaseHelper.instance,
        _coverageService = coverageService ?? InputCoverageService(db: db);

  final DatabaseHelper _db;
  final InputCoverageService _coverageService;

  /// Ensure epistemics exist for all roles×planes for a date.
  /// If user has not overridden q/c, defaults are derived from cov_plane.
  Future<void> ensureDefaultsForDate(DateTime date) async {
    final cov = await _coverageService.computeForDate(date);
    if (cov == null) return;

    final covByPlane = <String, double>{
      'ROOT.I': cov.covPlaneInternal,
      'ROOT.E': cov.covPlaneExternal,
      'ROOT.O': cov.covPlaneOutput,
    };

    for (final role in kCanonRoles) {
      for (final planeId in covByPlane.keys) {
        final covPlane = covByPlane[planeId]!;
        final qDefault = _clamp01(covPlane);
        final cDefault = _clamp01(0.85 * covPlane);

        await _db.upsertRolePlaneEpistemicsDefault(
          date: _yyyyMmDd(date),
          roleId: role.id,
          planeId: planeId,
          qDefault: qDefault,
          cDefault: cDefault,
          ruleId: CanonRuleIds.coverageV1,
        );
      }
    }
  }

  

Future<List<Map<String, Object?>>> listForDate(String dateYyyyMmDd) async {
  return _db.listRolePlaneEpistemics(dateYyyyMmDd);
}

Future<void> setOverride(DateTime date, {
  required String roleId,
  required String planeId,
  required double q,
  required double c,
}) async {
  await _db.upsertRolePlaneEpistemicsOverride(
    date: _yyyyMmDd(date),
    roleId: roleId,
    planeId: planeId,
    q: _clamp01(q),
    c: _clamp01(c),
    ruleId: 'user_override_v1',
  );
}

Future<void> revertToComputed(DateTime date, {
  required String roleId,
  required String planeId,
}) async {
  await _db.clearRolePlaneEpistemicsOverride(
    date: _yyyyMmDd(date),
    roleId: roleId,
    planeId: planeId,
  );
  // Re-apply defaults from coverage.
  await ensureDefaultsForDate(date);
}


  double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

  String _yyyyMmDd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
