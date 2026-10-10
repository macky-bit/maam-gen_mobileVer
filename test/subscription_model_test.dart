import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/subscription_plan.dart';
import 'package:stream_flix/models/playback_quality.dart';
import 'package:stream_flix/services/account_service.dart';
import 'package:stream_flix/services/subscription_service.dart';

void main() {
  test('limits demo playback quality to the active plan', () {
    expect(playbackQualitiesForPlan('Basic'), [480]);
    expect(playbackQualitiesForPlan('Standard'), [480, 720]);
    expect(playbackQualitiesForPlan('Premium'), [480, 720, 1080]);
    expect(preferredPlaybackQuality('Premium'), 1080);
    expect(requiredPlanForQuality(1080), 'Premium');
  });

  test('plan changes exclude the active subscription', () {
    final changes = availablePlanChanges(fallbackSubscriptionPlans, 2);
    expect(changes.map((plan) => plan.id), isNot(contains(2)));
    expect(changes, hasLength(fallbackSubscriptionPlans.length - 1));
  });
  test('maps a database plan and formats its peso price', () {
    final plan = SubscriptionPlan.fromJson({
      'subscription_id': 2,
      'plan_name': 'Standard',
      'monthly_price': 299,
      'max_user': 2,
    });

    expect(plan.id, 2);
    expect(plan.price, '\u20B1299');
    expect(plan.maxUsers, 2);
    expect(plan.recommended, isTrue);
  });

  test('maps an active subscription and its expiration timestamp', () {
    final status = SubscriptionStatus.fromJson({
      'is_active': true,
      'subscription_id': 3,
      'plan_name': 'Premium',
      'monthly_price': 499,
      'max_user': 4,
      'payment_date': '2026-09-29T11:30:00+00:00',
      'end_date': '2026-10-29T11:30:00+00:00',
    });

    expect(status.isActive, isTrue);
    expect(status.subscriptionId, 3);
    expect(status.planName, 'Premium');
    expect(status.monthlyPrice, 499);
    expect(status.maxUsers, 4);
    expect(status.paymentDate, DateTime.utc(2026, 9, 29, 11, 30));
    expect(status.endDate, DateTime.utc(2026, 10, 29, 11, 30));
  });

  test('maps editable account fields and read-only billing records', () {
    final settings = AccountSettings.fromJson({
      'first_name': 'Mark',
      'last_name': 'Lee',
      'email': 'mark@example.com',
      'date_of_birth': '2000-05-14',
      'plan_name': 'Premium',
      'monthly_price': 499,
      'max_user': 4,
      'payment_date': '2026-09-30T08:00:00+00:00',
      'payment_amount': 499,
      'end_date': '2026-10-30T08:00:00+00:00',
      'payment_method': 'prototype',
      'billing_history': [
        {
          'payment_id': 22,
          'amount': '499.00',
          'payment_method': 'Stripe',
          'reference_number': 'pi_latest',
          'status': 'Paid',
          'paid_at': '2026-09-30T08:00:00+00:00',
          'created_at': '2026-09-30T08:00:00+00:00',
        },
        {
          'payment_id': 21,
          'amount': 499,
          'payment_method': 'Stripe',
          'reference_number': 'pi_previous',
          'status': 'Paid',
          'paid_at': null,
          'created_at': '2026-08-30T08:00:00+00:00',
        },
      ],
    });

    expect(settings.firstName, 'Mark');
    expect(settings.birthDate, DateTime(2000, 5, 14));
    expect(settings.paymentAmount, 499);
    expect(settings.billingHistory, hasLength(2));
    expect(settings.billingHistory.first.id, '22');
    expect(settings.billingHistory.first.amount, 499);
    expect(settings.billingHistory.last.paidAt, DateTime.utc(2026, 8, 30, 8));
  });
}
