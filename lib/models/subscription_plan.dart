class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.description,
    required this.maxUsers,
    required this.features,
    this.recommended = false,
  });

  final String id;
  final String name;
  final String price;
  final String description;
  final int maxUsers;
  final List<String> features;
  final bool recommended;
}

const subscriptionPlans = [
  SubscriptionPlan(
    id: 'basic',
    name: 'Basic',
    price: '₱149',
    description: 'Great for casual viewers.',
    maxUsers: 1,
    features: [
      'Watch on 1 device at a time',
      'HD (720p) quality',
      'Download on 1 device',
      'Access to all available content',
    ],
  ),
  SubscriptionPlan(
    id: 'standard',
    name: 'Standard',
    price: '₱249',
    description: 'The perfect balance of quality and value.',
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
    id: 'premium',
    name: 'Premium',
    price: '₱349',
    description: 'The ultimate streaming experience.',
    maxUsers: 4,
    features: [
      'Watch on 4 devices at a time',
      '4K (UHD) + HDR quality',
      'Download on 4 devices',
      'Access to all available content',
    ],
  ),
];
