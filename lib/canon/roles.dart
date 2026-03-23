// lib/canon/roles.dart
// Canon role IDs for the 3×3 Role×Plane lattice.

enum CanonRole {
  observer('OBS'),
  governor('GOV'),
  grace('GRA');

  final String id;
  const CanonRole(this.id);
}

const List<CanonRole> kCanonRoles = [
  CanonRole.observer,
  CanonRole.governor,
  CanonRole.grace,
];
