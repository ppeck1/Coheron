// lib/canon/symbol_governance.dart
// CANON guardrails. Single source of truth for symbol names and key IDs.
// Do not edit without a patch entry.

class CanonSymbols {
  // Never use bare C: always index in code and UI labels.
  static const String C_rp = 'C_rp';
  static const String C_lattice = 'C_lattice';
  static const String C_tilde_rp = 'C_tilde_rp';
  static const String C_tilde_lattice = 'C_tilde_lattice';

  // Refresh is an EVENT, not a scalar R(t).
  static const String refreshEvent = 'R_REFRESH_EVENT'; // storage-safe token for ℛ_rp(t)

  // Visibility split
  static const String V_vis = 'V_vis';
  static const String V_verif = 'V_verif';

  // Decay vs propagation split
  static const String lambdaSub = 'lambda_sub'; // λ_sub (aggregate decay)
  static const String kSub = 'k_sub';           // k_sub(t) (cascade reactivity)
}

class CanonRuleIds {
  static const String coverageV1 = 'CR-COV-v1';
}
