import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription_plan.dart';

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.isActive,
    this.subscriptionId,
    this.planName,
    this.monthlyPrice,
    this.maxUsers,
    this.paymentDate,
    this.endDate,
  });

  final bool isActive;
  final int? subscriptionId;
  final String? planName;
  final double? monthlyPrice;
  final int? maxUsers;
  final DateTime? paymentDate;
  final DateTime? endDate;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      isActive: json['is_active'] as bool? ?? false,
      subscriptionId: (json['subscription_id'] as num?)?.toInt(),
      planName: json['plan_name'] as String?,
      monthlyPrice: (json['monthly_price'] as num?)?.toDouble(),
      maxUsers: (json['max_user'] as num?)?.toInt(),
      paymentDate: json['payment_date'] == null
          ? null
          : DateTime.parse(json['payment_date'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
    );
  }
}

class SubscriptionService {
  const SubscriptionService(this.client);

  final SupabaseClient client;

  Future<List<SubscriptionPlan>> fetchPlans() async {
    final rows = await client.rpc('get_subscription_plans') as List;
    return rows
        .map((row) => SubscriptionPlan.fromJson(row))
        .toList(growable: false);
  }

  Future<SubscriptionStatus> fetchStatus() async {
    final rows = await client.rpc('get_my_subscription_state') as List;
    if (rows.isEmpty) {
      throw StateError('Your StreamFlix profile could not be found.');
    }
    return SubscriptionStatus.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<SubscriptionCheckoutResult> startCheckout(
    SubscriptionPlan plan,
  ) async {
    final response = await client.functions.invoke(
      'create-checkout-session',
      body: {'planId': plan.id},
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('Stripe Checkout returned an invalid response.');
    }
    if (data['updated'] == true) {
      return const SubscriptionCheckoutResult(updated: true);
    }
    final checkoutUrl = Uri.tryParse(data['url']?.toString() ?? '');
    if (checkoutUrl == null ||
        checkoutUrl.scheme != 'https' ||
        checkoutUrl.host != 'checkout.stripe.com') {
      throw StateError('Stripe Checkout returned an invalid URL.');
    }
    return SubscriptionCheckoutResult(checkoutUrl: checkoutUrl);
  }
}

class SubscriptionCheckoutResult {
  const SubscriptionCheckoutResult({this.updated = false, this.checkoutUrl});

  final bool updated;
  final Uri? checkoutUrl;
}
