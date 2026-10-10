const playbackQualities = [480, 720, 1080];

List<int> playbackQualitiesForPlan(String? planName) {
  return switch (planName?.trim().toLowerCase()) {
    'premium' => playbackQualities,
    'standard' => playbackQualities.take(2).toList(growable: false),
    _ => playbackQualities.take(1).toList(growable: false),
  };
}

int preferredPlaybackQuality(String? planName) =>
    playbackQualitiesForPlan(planName).last;

String playbackAssetForQuality(int quality) =>
    'assets/media/${quality}MovieStudioLogo.mp4';

String requiredPlanForQuality(int quality) => switch (quality) {
  1080 => 'Premium',
  720 => 'Standard',
  _ => 'Basic',
};
