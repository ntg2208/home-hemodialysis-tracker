class RateOverride {
  const RateOverride({this.perSession, this.targetQty});
  final int? perSession;
  final int? targetQty;

  Map<String, dynamic> toJson() => {
    if (perSession != null) 'perSession': perSession,
    if (targetQty != null) 'targetQty': targetQty,
  };

  factory RateOverride.fromJson(Map<dynamic, dynamic> m) => RateOverride(
    perSession: (m['perSession'] as num?)?.toInt(),
    targetQty: (m['targetQty'] as num?)?.toInt(),
  );
}
