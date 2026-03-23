// lib/services/series_registry.dart
// Atlas v2.3 — Domain / Plane / Indicator vocabulary only.

import '../database/database_helper.dart';
import '../models/series_spec.dart';
import 'taxonomy_service.dart';

class SeriesRegistry {
  final TaxonomyService taxonomy;
  final DatabaseHelper db;

  SeriesRegistry({required this.taxonomy, required this.db});

  /// Domain-level series (ROOT.*  — Internal, External, Output).
  List<SeriesSpec> domains() => taxonomy
      .getDomainIds()
      .map((id) => SeriesSpec(
            id: id,
            label: taxonomy.labelFor(id),
            type: SeriesType.taxonomy,
            scope: SeriesScope.domain,
            unit: '%',
          ))
      .toList();

  /// Plane-level series for a domain (L2.*).
  List<SeriesSpec> planesForDomain(String domainId) => taxonomy
      .getPlanesForDomain(domainId)
      .map((id) => SeriesSpec(
            id: id,
            label: taxonomy.labelFor(id),
            type: SeriesType.taxonomy,
            scope: SeriesScope.plane,
            unit: '%',
          ))
      .toList();

  /// Indicator-level series for a plane (LEAF.*).
  List<SeriesSpec> indicatorsForPlane(String planeId) => taxonomy
      .getIndicatorsForPlane(planeId)
      .map((id) => SeriesSpec(
            id: id,
            label: taxonomy.labelFor(id),
            type: SeriesType.taxonomy,
            scope: SeriesScope.indicator,
            unit: '%',
          ))
      .toList();

  List<SeriesSpec> frequencyAxes() => const [
        SeriesSpec(id: 'FREQ.SENSE',    label: 'Sense',    type: SeriesType.frequency, scope: SeriesScope.reflection, unit: '%'),
        SeriesSpec(id: 'FREQ.MAINTAIN', label: 'Maintain', type: SeriesType.frequency, scope: SeriesScope.reflection, unit: '%'),
        SeriesSpec(id: 'FREQ.EXPLORE',  label: 'Explore',  type: SeriesType.frequency, scope: SeriesScope.reflection, unit: '%'),
        SeriesSpec(id: 'FREQ.ENFORCE',  label: 'Enforce',  type: SeriesType.frequency, scope: SeriesScope.reflection, unit: '%'),
      ];

  Future<List<SeriesSpec>> vitals() async {
    final base = <SeriesSpec>[
      const SeriesSpec(id: 'VITAL.hr',      label: 'Heart rate',   type: SeriesType.vitals, scope: SeriesScope.vital, unit: 'bpm'),
      const SeriesSpec(id: 'VITAL.bp_sys',  label: 'BP systolic',  type: SeriesType.vitals, scope: SeriesScope.vital, unit: 'mmHg'),
      const SeriesSpec(id: 'VITAL.bp_dia',  label: 'BP diastolic', type: SeriesType.vitals, scope: SeriesScope.vital, unit: 'mmHg'),
      const SeriesSpec(id: 'VITAL.temp',    label: 'Temperature',  type: SeriesType.vitals, scope: SeriesScope.vital, unit: '°'),
      const SeriesSpec(id: 'VITAL.spo2',    label: 'SpO₂',         type: SeriesType.vitals, scope: SeriesScope.vital, unit: '%'),
      const SeriesSpec(id: 'VITAL.glucose', label: 'Glucose',       type: SeriesType.vitals, scope: SeriesScope.vital, unit: ''),
    ];
    final customs = await db.getCustomVitalSpecs();
    return [...base, ...customs];
  }

  Future<List<SeriesSpec>> allSeries() async {
    final out = <SeriesSpec>[];
    out.addAll(domains());
    for (final domainId in taxonomy.getDomainIds()) {
      for (final planeId in taxonomy.getPlanesForDomain(domainId)) {
        out.add(SeriesSpec(
            id: planeId,
            label: taxonomy.labelFor(planeId),
            type: SeriesType.taxonomy,
            scope: SeriesScope.plane,
            unit: '%'));
        for (final indicatorId in taxonomy.getIndicatorsForPlane(planeId)) {
          out.add(SeriesSpec(
              id: indicatorId,
              label: taxonomy.labelFor(indicatorId),
              type: SeriesType.taxonomy,
              scope: SeriesScope.indicator,
              unit: '%'));
        }
      }
    }
    out.addAll(frequencyAxes());
    out.addAll(await vitals());
    return out;
  }
}
