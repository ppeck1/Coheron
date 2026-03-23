// lib/taxonomy/taxonomy_locked.dart
// LOCKED TAXONOMY v2.0 — IDs are canonical and must never change.
// Labels updated to match Atlas v2.0 locked spec.
// Hierarchy: Domains → Planes → Indicators  (3 × 3 × 3)
// tensor[domain][plane][indicator]

class MetricNode {
  final String id;
  final String label;
  final String description;
  final List<String> children;

  const MetricNode({
    required this.id,
    required this.label,
    required this.description,
    this.children = const [],
  });

  bool get isDomain    => id.startsWith('ROOT.');
  bool get isPlane     => id.startsWith('L2.');
  bool get isIndicator => id.startsWith('LEAF.');
}

const Map<String, MetricNode> kTaxonomy = {

  // ── Domains ─────────────────────────────────────────────────────────────────
  'ROOT.I': MetricNode(id: 'ROOT.I', label: 'Internal',
    description: 'Internal state: body, attention, and affect.',
    children: ['L2.I.1', 'L2.I.2', 'L2.I.3'],
  ),
  'ROOT.E': MetricNode(id: 'ROOT.E', label: 'External',
    description: 'External context: safety, support, and demands.',
    children: ['L2.E.1', 'L2.E.2', 'L2.E.3'],
  ),
  'ROOT.O': MetricNode(id: 'ROOT.O', label: 'Output',
    description: 'Output capacity: follow-through, activity, and recovery.',
    children: ['L2.O.1', 'L2.O.2', 'L2.O.3'],
  ),

  // ── Planes: Internal ───────────────────────────────────────────────────────
  'L2.I.1': MetricNode(id: 'L2.I.1', label: 'Body',
    description: 'Physical state: sleep quality, pain, and energy.',
    children: ['LEAF.I.1.1', 'LEAF.I.1.2', 'LEAF.I.1.3'],
  ),
  'L2.I.2': MetricNode(id: 'L2.I.2', label: 'Attention',
    description: 'Cognitive state: attention, overwhelm, and mental noise.',
    children: ['LEAF.I.2.1', 'LEAF.I.2.2', 'LEAF.I.2.3'],
  ),
  'L2.I.3': MetricNode(id: 'L2.I.3', label: 'Affect',
    description: 'Affective state: anxiety, mood, and drive.',
    children: ['LEAF.I.3.1', 'LEAF.I.3.2', 'LEAF.I.3.3'],
  ),

  // ── Planes: External ───────────────────────────────────────────────────────
  'L2.E.1': MetricNode(id: 'L2.E.1', label: 'Safety',
    description: 'Physical and environmental safety: security, stability, and threat.',
    children: ['LEAF.E.1.1', 'LEAF.E.1.2', 'LEAF.E.1.3'],
  ),
  'L2.E.2': MetricNode(id: 'L2.E.2', label: 'Support',
    description: 'Relational context: connection, conflict, and cooperation.',
    children: ['LEAF.E.2.1', 'LEAF.E.2.2', 'LEAF.E.2.3'],
  ),
  'L2.E.3': MetricNode(id: 'L2.E.3', label: 'Demands',
    description: 'External load: workload, time pressure, and complexity.',
    children: ['LEAF.E.3.1', 'LEAF.E.3.2', 'LEAF.E.3.3'],
  ),

  // ── Planes: Output ─────────────────────────────────────────────────────────
  'L2.O.1': MetricNode(id: 'L2.O.1', label: 'Follow-through',
    description: 'Task execution: completion, reactivity, and drift.',
    children: ['LEAF.O.1.1', 'LEAF.O.1.2', 'LEAF.O.1.3'],
  ),
  'L2.O.2': MetricNode(id: 'L2.O.2', label: 'Activity',
    description: 'Life-shape: movement, intake, and rhythm.',
    children: ['LEAF.O.2.1', 'LEAF.O.2.2', 'LEAF.O.2.3'],
  ),
  'L2.O.3': MetricNode(id: 'L2.O.3', label: 'Recovery',
    description: 'Self-regulation: restoration, soothing, and release.',
    children: ['LEAF.O.3.1', 'LEAF.O.3.2', 'LEAF.O.3.3'],
  ),

  // ── Indicators: Internal › Body ──────────────────────────────────────────
  'LEAF.I.1.1': MetricNode(id: 'LEAF.I.1.1', label: 'Rest',
    description: 'Quality and adequacy of recent sleep or rest (0=poor, 100=excellent).',
  ),
  'LEAF.I.1.2': MetricNode(id: 'LEAF.I.1.2', label: 'Pain',
    description: 'Physical pain or discomfort level (0=none, 100=severe).',
  ),
  'LEAF.I.1.3': MetricNode(id: 'LEAF.I.1.3', label: 'Energy',
    description: 'Subjective physical energy and vitality (0=depleted, 100=high).',
  ),

  // ── Indicators: Internal › Attention ─────────────────────────────────────────
  'LEAF.I.2.1': MetricNode(id: 'LEAF.I.2.1', label: 'Focus',
    description: 'Ability to direct and sustain attention (0=scattered, 100=sharp).',
  ),
  'LEAF.I.2.2': MetricNode(id: 'LEAF.I.2.2', label: 'Overwhelm',
    description: 'Sense of cognitive overload (0=none, 100=extreme).',
  ),
  'LEAF.I.2.3': MetricNode(id: 'LEAF.I.2.3', label: 'Noise',
    description: 'Intrusive thoughts or mental background noise (0=quiet, 100=loud).',
  ),

  // ── Indicators: Internal › Affect ───────────────────────────────────────
  'LEAF.I.3.1': MetricNode(id: 'LEAF.I.3.1', label: 'Anxiety',
    description: 'Presence and intensity of anxiety or worry (0=none, 100=intense).',
  ),
  'LEAF.I.3.2': MetricNode(id: 'LEAF.I.3.2', label: 'Mood',
    description: 'Overall emotional valence (0=very low, 100=very positive).',
  ),
  'LEAF.I.3.3': MetricNode(id: 'LEAF.I.3.3', label: 'Drive',
    description: 'Motivation and sense of direction (0=none, 100=strong).',
  ),

  // ── Indicators: External › Safety ────────────────────────────────────────
  'LEAF.E.1.1': MetricNode(id: 'LEAF.E.1.1', label: 'Physical Safety',
    description: 'Felt sense of physical safety (0=unsafe, 100=safe).',
  ),
  'LEAF.E.1.2': MetricNode(id: 'LEAF.E.1.2', label: 'Environmental Stability',
    description: 'Stability and predictability of surroundings (0=chaotic, 100=stable).',
  ),
  'LEAF.E.1.3': MetricNode(id: 'LEAF.E.1.3', label: 'Threat',
    description: 'Active or perceived threat level (0=none, 100=severe).',
  ),

  // ── Indicators: External › Support ──────────────────────────────────────
  'LEAF.E.2.1': MetricNode(id: 'LEAF.E.2.1', label: 'Connection',
    description: 'Quality of social connection and belonging (0=isolated, 100=connected).',
  ),
  'LEAF.E.2.2': MetricNode(id: 'LEAF.E.2.2', label: 'Conflict',
    description: 'Active interpersonal tension or conflict (0=none, 100=severe).',
  ),
  'LEAF.E.2.3': MetricNode(id: 'LEAF.E.2.3', label: 'Cooperation',
    description: 'Degree of collaborative support in environment (0=none, 100=high).',
  ),

  // ── Indicators: External › Demands ──────────────────────────────────────
  'LEAF.E.3.1': MetricNode(id: 'LEAF.E.3.1', label: 'Workload',
    description: 'Volume of tasks and obligations (0=none, 100=overwhelming).',
  ),
  'LEAF.E.3.2': MetricNode(id: 'LEAF.E.3.2', label: 'Time Pressure',
    description: 'Urgency and deadline pressure (0=none, 100=extreme).',
  ),
  'LEAF.E.3.3': MetricNode(id: 'LEAF.E.3.3', label: 'Complexity',
    description: 'Cognitive complexity of current demands (0=simple, 100=extreme).',
  ),

  // ── Indicators: Output › Follow-through ──────────────────────────────────
  'LEAF.O.1.1': MetricNode(id: 'LEAF.O.1.1', label: 'Task Completion',
    description: 'Completing what you started (0=unable, 100=consistent).',
  ),
  'LEAF.O.1.2': MetricNode(id: 'LEAF.O.1.2', label: 'Reactivity',
    description: 'Degree of reactive vs intentional task switching (0=intentional, 100=highly reactive).',
  ),
  'LEAF.O.1.3': MetricNode(id: 'LEAF.O.1.3', label: 'Drift',
    description: 'Deviation from intended priorities (0=on track, 100=far off).',
  ),

  // ── Indicators: Output › Activity ────────────────────────────────────────
  'LEAF.O.2.1': MetricNode(id: 'LEAF.O.2.1', label: 'Movement',
    description: 'Physical movement and exercise today (0=none, 100=high).',
  ),
  'LEAF.O.2.2': MetricNode(id: 'LEAF.O.2.2', label: 'Intake',
    description: 'Quality of food, drink, and substance intake (0=poor, 100=good).',
  ),
  'LEAF.O.2.3': MetricNode(id: 'LEAF.O.2.3', label: 'Rhythm',
    description: 'Consistency of daily routines and timing (0=chaotic, 100=stable).',
  ),

  // ── Indicators: Output › Recovery ────────────────────────────────────────
  'LEAF.O.3.1': MetricNode(id: 'LEAF.O.3.1', label: 'Restoration',
    description: 'Ability to return to baseline after stress (0=unable, 100=fast).',
  ),
  'LEAF.O.3.2': MetricNode(id: 'LEAF.O.3.2', label: 'Soothing',
    description: 'Access to and use of healthy self-soothing (0=none, 100=effective).',
  ),
  'LEAF.O.3.3': MetricNode(id: 'LEAF.O.3.3', label: 'Release',
    description: 'Ability to discharge tension or stress (0=stuck, 100=released).',
  ),
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// The 3 domain IDs (top tier).
List<String> getDomainIds() => const ['ROOT.I', 'ROOT.E', 'ROOT.O'];

/// The 9 plane IDs (L2 tier, across all domains).
List<String> getPlaneIds() => const [
  'L2.I.1', 'L2.I.2', 'L2.I.3',
  'L2.E.1', 'L2.E.2', 'L2.E.3',
  'L2.O.1', 'L2.O.2', 'L2.O.3',
];

/// Plane IDs for a specific domain.
List<String> getPlanesForDomain(String domainId) =>
    kTaxonomy[domainId]?.children ?? const [];

/// Indicator IDs for a specific plane.
List<String> getIndicatorsForPlane(String planeId) =>
    kTaxonomy[planeId]?.children ?? const [];

String getLabel(String id) => kTaxonomy[id]?.label ?? prettyMetricId(id);

String prettyMetricId(String id) {
  final node = kTaxonomy[id];
  if (node != null) return node.label;
  return id
      .replaceFirst('ROOT.', 'Domain ')
      .replaceFirst('L2.', 'Plane ')
      .replaceFirst('LEAF.', 'Indicator ');
}

String getDescription(String id) => kTaxonomy[id]?.description ?? '';

/// Returns the domain ID (ROOT.*) for any metric ID.
String? getDomainForId(String id) {
  if (id.startsWith('ROOT.')) return id;
  if (id.startsWith('L2.') || id.startsWith('LEAF.')) {
    if (id.contains('.I.') || id == 'L2.I.1' || id == 'L2.I.2' || id == 'L2.I.3') return 'ROOT.I';
    if (id.contains('.E.') || id == 'L2.E.1' || id == 'L2.E.2' || id == 'L2.E.3') return 'ROOT.E';
    if (id.contains('.O.') || id == 'L2.O.1' || id == 'L2.O.2' || id == 'L2.O.3') return 'ROOT.O';
  }
  return null;
}

/// Returns the plane ID (L2.*) for a given ID.
/// - For a domain (ROOT.*): returns null (domains are above planes).
/// - For a plane (L2.*): returns itself.
/// - For an indicator (LEAF.*): returns its parent plane.
String? getPlaneForId(String id) {
  if (id.startsWith('L2.')) return id;
  if (id.startsWith('LEAF.')) {
    // LEAF.I.1.1 → L2.I.1,  LEAF.E.2.3 → L2.E.2, etc.
    final parts = id.split('.');
    if (parts.length >= 4) return '${parts[0].replaceFirst('LEAF', 'L2')}.${parts[1]}.${parts[2]}';
  }
  return null;
}

void assertTaxonomyValid() {
  assert(() {
    assert(kTaxonomy.length == 39, 'Expected 39 nodes, got ${kTaxonomy.length}');
    for (final node in kTaxonomy.values) {
      for (final child in node.children) {
        assert(kTaxonomy.containsKey(child),
            'Child $child not found (parent: ${node.id})');
      }
    }
    for (final domainId in getDomainIds()) {
      final planes = getPlanesForDomain(domainId);
      assert(planes.length == 3, 'Domain $domainId needs exactly 3 planes');
      for (final planeId in planes) {
        final indicators = getIndicatorsForPlane(planeId);
        assert(indicators.length == 3, 'Plane $planeId needs exactly 3 indicators');
      }
    }
    assert(getPlaneIds().length == 9, 'Expected 9 planes, got ${getPlaneIds().length}');
    return true;
  }());
}

/// All 27 indicator IDs (LEAF tier).
List<String> getIndicatorIds() {
  final result = <String>[];
  for (final domainId in getDomainIds()) {
    for (final planeId in getPlanesForDomain(domainId)) {
      result.addAll(getIndicatorsForPlane(planeId));
    }
  }
  return result;
}

/// Label for a domain ID.
String getDomainLabel(String domainId) => getLabel(domainId);

/// Label for a plane ID.
String getPlaneLabel(String planeId) => getLabel(planeId);

/// Label for an indicator ID.
String getIndicatorLabel(String indicatorId) => getLabel(indicatorId);

/// Whether [id] is an indicator (LEAF tier).
bool isIndicator(String id) => id.startsWith('LEAF.');

String labelForMetricId(String id) {
  final node = kTaxonomy[id];
  if (node != null) return node.label;
  return prettyMetricId(id);
}
