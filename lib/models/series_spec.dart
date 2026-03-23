enum SeriesType { taxonomy, frequency, vitals, derived }

/// Scope levels in the Domain → Plane → Indicator hierarchy.
enum SeriesScope {
  domain,     // ROOT.* — top tier
  plane,      // L2.*   — middle tier
  indicator,  // LEAF.* — bottom tier
  reflection,
  vital,
}

class SeriesSpec {
  final String id;
  final String label;
  final SeriesType type;
  final String? unit;
  final SeriesScope scope;

  const SeriesSpec({
    required this.id,
    required this.label,
    required this.type,
    required this.scope,
    this.unit,
  });
}
