class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    required this.description,
    required this.maxUsers,
    required this.features,
    this.recommended = false,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final maxUsers = (json['max_user'] as num).toInt();
    final name = json['plan_name'] as String;
    return SubscriptionPlan(
      id: (json['subscription_id'] as num).toInt(),
      name: name,
      monthlyPrice: (json['monthly_price'] as num).toDouble(),
      description: switch (name.toLowerCase()) {
        'basic' => 'One-profile plan with full access',
        'standard' => 'Two-profile plan with full access',
        'premium' => 'Four-profile plan with full access',
        _ => 'Monthly StreamFlix access',
      },
      maxUsers: maxUsers,
      recommended: (json['subscription_id'] as num).toInt() == 2,
      features: [
        'Watch on $maxUsers ${maxUsers == 1 ? 'device' : 'devices'} at a time',
        'Access to all available content',
      ],
    );
  }

  final int id;
  final String name;
  final double monthlyPrice;
  final String description;
  final int maxUsers;
  final List<String> features;
  final bool recommended;

  String get price {
    final hasFraction = monthlyPrice != monthlyPrice.roundToDouble();
    return '\u20B1${monthlyPrice.toStringAsFixed(hasFraction ? 2 : 0)}';
  }
}

const fallbackSubscriptionPlans = [
  SubscriptionPlan(
    id: 1,
    name: 'Basic',
    monthlyPrice: 199,
    description: 'One-profile plan with full access',
    maxUsers: 1,
    features: [
      'Watch on 1 device at a time',
      'HD (720p) quality',
      'Download on 1 device',
      'Access to all available content',
    ],
  ),
  SubscriptionPlan(
    id: 2,
    name: 'Standard',
    monthlyPrice: 299,
    description: 'Two-profile plan with full access',
    maxUsers: 2,
    recommended: true,
    features: [
      'Watch on 2 devices at a time',
      'Full HD (1080p) quality',
      'Download on 2 devices',
      'Access to all available content',
    ],
  ),
  SubscriptionPlan(
    id: 3,
    name: 'Premium',
    monthlyPrice: 499,
    description: 'Four-profile plan with full access',
    maxUsers: 4,
    features: [
      'Watch on 4 devices at a time',
      '4K (UHD) + HDR quality',
      'Download on 4 devices',
      'Access to all available content',
    ],
  ),
];
