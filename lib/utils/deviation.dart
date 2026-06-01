/// Deviation / variance calculations for WasteTrack (per spec).
/// Default thresholds: >5% OR >50kg (whichever triggers first).
class DeviationResult {
  final double recordedWeightKg;
  final double actualWeightKg;
  final double varianceKg;
  final double variancePercent;
  final bool isDeviation;
  final double thresholdPercent;
  final double thresholdKg;

  const DeviationResult({
    required this.recordedWeightKg,
    required this.actualWeightKg,
    required this.varianceKg,
    required this.variancePercent,
    required this.isDeviation,
    required this.thresholdPercent,
    required this.thresholdKg,
  });
}

/// Calculates weight variance and whether it triggers deviation alert.
DeviationResult calculateDeviation({
  required double recordedWeightKg,
  required double actualWeightKg,
  double thresholdPercent = 5.0,
  double thresholdKg = 50.0,
}) {
  if (actualWeightKg <= 0) {
    return DeviationResult(
      recordedWeightKg: recordedWeightKg,
      actualWeightKg: actualWeightKg,
      varianceKg: 0,
      variancePercent: 0,
      isDeviation: false,
      thresholdPercent: thresholdPercent,
      thresholdKg: thresholdKg,
    );
  }

  final varianceKg = actualWeightKg - recordedWeightKg;
  final variancePercent = (varianceKg / actualWeightKg) * 100;

  final isDeviation = variancePercent.abs() > thresholdPercent ||
      varianceKg.abs() > thresholdKg;

  return DeviationResult(
    recordedWeightKg: recordedWeightKg,
    actualWeightKg: actualWeightKg,
    varianceKg: varianceKg,
    variancePercent: variancePercent,
    isDeviation: isDeviation,
    thresholdPercent: thresholdPercent,
    thresholdKg: thresholdKg,
  );
}
