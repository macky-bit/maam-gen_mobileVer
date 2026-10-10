import 'package:supabase_flutter/supabase_flutter.dart';

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

  factory AccountSettings.fromJson(Map<String, dynamic> json) {
    return AccountSettings(
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      birthDate: json['date_of_birth'] == null
          ? null
          : DateTime.parse(json['date_of_birth'] as String),
      planName: json['plan_name'] as String?,
      monthlyPrice: (json['monthly_price'] as num?)?.toDouble(),
      maxUsers: (json['max_user'] as num?)?.toInt(),
      paymentDate: json['payment_date'] == null
          ? null
          : DateTime.parse(json['payment_date'] as String),
      paymentAmount: (json['payment_amount'] as num?)?.toDouble(),
      subscriptionEnd: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      paymentMethod: json['payment_method'] as String?,
    );
  }
}

class AccountService {
  const AccountService(this.client);

  final SupabaseClient client;

  Future<AccountSettings> fetchSettings() async {
    final rows = await client.rpc('get_my_account_settings') as List;
    if (rows.isEmpty) throw StateError('Account details were not found.');
    return AccountSettings.fromJson(rows.first as Map<String, dynamic>);
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
}
