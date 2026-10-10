import 'package:supabase_flutter/supabase_flutter.dart';

class BillingTransaction {
  const BillingTransaction({
    required this.id,
    required this.amount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.status,
    required this.paidAt,
  });

  final String id;
  final double amount;
  final String? paymentMethod;
  final String? referenceNumber;
  final String status;
  final DateTime paidAt;

  factory BillingTransaction.fromJson(Map<String, dynamic> json) {
    return BillingTransaction(
      id: json['payment_id'].toString(),
      amount: _number(json['amount']) ?? 0,
      paymentMethod: json['payment_method'] as String?,
      referenceNumber: json['reference_number'] as String?,
      status: json['status'] as String? ?? 'Unknown',
      paidAt: DateTime.parse(
        (json['paid_at'] ?? json['created_at']).toString(),
      ),
    );
  }
}

class AccountSettings {
  const AccountSettings({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.birthDate,
    required this.planName,
    required this.monthlyPrice,
    required this.maxUsers,
    required this.paymentDate,
    required this.paymentAmount,
    required this.subscriptionEnd,
    required this.paymentMethod,
    required this.billingHistory,
  });

  final String firstName;
  final String lastName;
  final String email;
  final DateTime? birthDate;
  final String? planName;
  final double? monthlyPrice;
  final int? maxUsers;
  final DateTime? paymentDate;
  final double? paymentAmount;
  final DateTime? subscriptionEnd;
  final String? paymentMethod;
  final List<BillingTransaction> billingHistory;

  factory AccountSettings.fromJson(Map<String, dynamic> json) {
    final paymentDate = json['payment_date'] == null
        ? null
        : DateTime.parse(json['payment_date'] as String);
    final paymentAmount = _number(json['payment_amount']);
    final history = (json['billing_history'] as List? ?? const [])
        .map((row) => BillingTransaction.fromJson(row as Map<String, dynamic>))
        .toList(growable: true);
    if (history.isEmpty && paymentDate != null && paymentAmount != null) {
      history.add(
        BillingTransaction(
          id: 'account-payment-${paymentDate.toIso8601String()}',
          amount: paymentAmount,
          paymentMethod: json['payment_method'] as String?,
          referenceNumber: null,
          status: 'Paid',
          paidAt: paymentDate,
        ),
      );
    }
    return AccountSettings(
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      birthDate: json['date_of_birth'] == null
          ? null
          : DateTime.parse(json['date_of_birth'] as String),
      planName: json['plan_name'] as String?,
      monthlyPrice: _number(json['monthly_price']),
      maxUsers: (json['max_user'] as num?)?.toInt(),
      paymentDate: paymentDate,
      paymentAmount: paymentAmount,
      subscriptionEnd: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      paymentMethod: json['payment_method'] as String?,
      billingHistory: List.unmodifiable(history),
    );
  }
}

double? _number(Object? value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};

class AccountService {
  const AccountService(this.client);

  final SupabaseClient client;

  Future<AccountSettings> fetchSettings() async {
    final authId = client.auth.currentUser?.id;
    if (authId == null) throw StateError('Sign in to view billing details.');
    final rows = await client.rpc('get_my_account_settings') as List;
    if (rows.isEmpty) throw StateError('Account details were not found.');
    final account = await client
        .from('user')
        .select('user_id')
        .eq('auth_user_id', authId)
        .single();
    final payments = await client
        .from('payment_transaction')
        .select(
          'payment_id, amount, payment_method, reference_number, status, '
          'paid_at, created_at',
        )
        .eq('user_id', account['user_id'])
        .order('created_at', ascending: false)
        .limit(12);
    return AccountSettings.fromJson({
      ...rows.first as Map<String, dynamic>,
      'billing_history': payments,
    });
  }

  Future<void> updateBirthDate(DateTime date) async {
    final value =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    await client.rpc(
      'update_my_birth_date',
      params: {'selected_birth_date': value},
    );
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
  }) async {
    final date =
        '${birthDate.year.toString().padLeft(4, '0')}-'
        '${birthDate.month.toString().padLeft(2, '0')}-'
        '${birthDate.day.toString().padLeft(2, '0')}';
    await client.rpc(
      'update_my_account_profile',
      params: {
        'selected_first_name': firstName.trim(),
        'selected_last_name': lastName.trim(),
        'selected_birth_date': date,
      },
    );
  }

  Future<void> requestEmailChange(String email) async {
    await client.auth.updateUser(UserAttributes(email: email.trim()));
  }

  Future<void> changePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> setProfilePin(int profileId, String? pin) async {
    await client.rpc(
      'set_my_member_profile_pin',
      params: {
        'selected_profile_id': profileId,
        'selected_pin': pin?.trim().isEmpty == true ? null : pin?.trim(),
      },
    );
  }

  Future<void> submitSupportRequest({
    required String subject,
    required String description,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to contact support.');
    final account = await client
        .from('user')
        .select('user_id')
        .eq('auth_user_id', user.id)
        .single();
    await client.from('platform_feedback').insert({
      'user_id': account['user_id'],
      'feedback_type': 'Support Request',
      'subject': subject.trim(),
      'description': '[Mobile app]\n${description.trim()}',
      'screenshot': null,
      'status': 'Open',
    });
  }
}
