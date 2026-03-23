// lib/services/taxonomy_service.dart
// Atlas v2.3a — Final semantic lock.
//
// Single hierarchy:  Domain → Plane → Indicator
// Single level type: TaxonomyLevel { domain, plane, indicator }
// No compatibility aliases. No cross-hierarchy shims.

import '../taxonomy/taxonomy_locked.dart' as tl;

/// Hierarchy level in Domain → Plane → Indicator.
enum TaxonomyLevel { domain, plane, indicator }

class TaxonomyService {
  const TaxonomyService();

  // ── ID collections ─────────────────────────────────────────────────────────

  List<String> getDomainIds()    => tl.getDomainIds();
  List<String> getPlaneIds()     => tl.getPlaneIds();
  List<String> getIndicatorIds() => tl.getIndicatorIds();

  // ── Parent-child helpers ───────────────────────────────────────────────────

  List<String> getPlanesForDomain(String domainId)     => tl.getPlanesForDomain(domainId);
  List<String> getIndicatorsForPlane(String planeId)   => tl.getIndicatorsForPlane(planeId);

  String? getDomainForPlane(String planeId)            => tl.getDomainForId(planeId);
  String? getPlaneForIndicator(String indicatorId)     => tl.getPlaneForId(indicatorId);

  // ── Label helpers ──────────────────────────────────────────────────────────

  String getDomainLabel(String domainId)       => tl.getLabel(domainId);
  String getPlaneLabel(String planeId)         => tl.getLabel(planeId);
  String getIndicatorLabel(String indicatorId) => tl.getLabel(indicatorId);
  String labelFor(String id)                   => tl.getLabel(id);

  // ── Level detection ────────────────────────────────────────────────────────

  TaxonomyLevel getTaxonomyLevelForId(String id) {
    if (id.startsWith('ROOT.')) return TaxonomyLevel.domain;
    if (id.startsWith('L2.'))   return TaxonomyLevel.plane;
    return TaxonomyLevel.indicator;
  }

  // ── Breadcrumb ─────────────────────────────────────────────────────────────

  String labelPath(String domainId, [String? planeId, String? indicatorId]) {
    final parts = <String>[labelFor(domainId)];
    if (planeId != null)    parts.add(labelFor(planeId));
    if (indicatorId != null) parts.add(labelFor(indicatorId));
    return parts.where((s) => s.isNotEmpty).join(' / ');
  }
}
