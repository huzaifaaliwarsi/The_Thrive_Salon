import 'dart:convert';

class Staff {
  final String id;
  final String name;
  final String? role;
  final String? phone;
  final String? salonId;
  final String? userId;
  final String? salaryType;
  final String? salaryValue;
  final String? commissionPercentage;
  final double? balance;
  final Map<String, dynamic>? user;
  final String? createdAt;
  final String? inTimeLimit;
  final String? outTimeLimit;
  final String? lateTimeLimit;
  final String? earlyExitTimeLimit;
  final String? lateDeductionRate;
  final String? earlyExitDeductionRate;
  final int? allowedLeaves;
  final String? joiningDate;
  final String? biometricPin;

  Staff({
    required this.id,
    required this.name,
    this.role,
    this.phone,
    this.salonId,
    this.userId,
    this.salaryType,
    this.salaryValue,
    this.commissionPercentage,
    this.balance,
    this.user,
    this.createdAt,
    this.inTimeLimit,
    this.outTimeLimit,
    this.lateTimeLimit,
    this.earlyExitTimeLimit,
    this.lateDeductionRate,
    this.earlyExitDeductionRate,
    this.allowedLeaves,
    this.joiningDate,
    this.biometricPin,
  });

  factory Staff.fromJson(Map<String, dynamic> json) {
    dynamic user = json['user'];
    if (user is String) {
      try {
        user = jsonDecode(user);
      } catch (_) {
        user = null;
      }
    }

    return Staff(
      id: json['id'].toString(),
      name: json['name'] ?? 'Unknown',
      role: json['role'] ?? user?['role'],
      phone: json['phone']?.toString(),
      salonId: json['salonId']?.toString(),
      userId: json['userId']?.toString(),
      salaryType: json['salaryType']?.toString(),
      salaryValue: json['salaryValue']?.toString(),
      commissionPercentage: json['commissionPercentage']?.toString(),
      balance: double.tryParse(json['balance']?.toString() ?? '0'),
      user: user as Map<String, dynamic>?,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      inTimeLimit: json['inTimeLimit']?.toString() ?? json['in_time_limit']?.toString(),
      outTimeLimit: json['outTimeLimit']?.toString() ?? json['out_time_limit']?.toString(),
      lateTimeLimit: json['lateTimeLimit']?.toString() ?? json['late_time_limit']?.toString(),
      earlyExitTimeLimit: json['earlyExitTimeLimit']?.toString() ?? json['early_exit_time_limit']?.toString(),
      lateDeductionRate: json['lateDeductionRate']?.toString() ?? json['late_deduction_rate']?.toString(),
      earlyExitDeductionRate: json['earlyExitDeductionRate']?.toString() ?? json['early_exit_deduction_rate']?.toString(),
      allowedLeaves: int.tryParse(json['allowedLeaves']?.toString() ?? json['allowed_leaves']?.toString() ?? '0'),
      joiningDate: json['joiningDate']?.toString() ?? json['joining_date']?.toString(),
      biometricPin: json['biometricPin']?.toString() ?? json['biometric_pin']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'phone': phone,
    'salonId': salonId,
    'userId': userId,
    'salaryType': salaryType,
    'salaryValue': salaryValue,
    'commissionPercentage': commissionPercentage,
    'balance': balance,
    'user': user,
    'createdAt': createdAt,
    'inTimeLimit': inTimeLimit,
    'outTimeLimit': outTimeLimit,
    'lateTimeLimit': lateTimeLimit,
    'earlyExitTimeLimit': earlyExitTimeLimit,
    'lateDeductionRate': lateDeductionRate,
    'earlyExitDeductionRate': earlyExitDeductionRate,
    'allowedLeaves': allowedLeaves,
    'joiningDate': joiningDate,
    'biometricPin': biometricPin,
  };

  Map<String, dynamic> toDb() => {
    'id': id,
    'name': name,
    'role': role,
    'phone': phone,
    'salonId': salonId,
    'userId': userId,
    'salaryType': salaryType,
    'salaryValue': salaryValue,
    'commissionPercentage': commissionPercentage,
    'balance': balance,
    'user': user != null ? jsonEncode(user) : null,
    'createdAt': createdAt,
    'inTimeLimit': inTimeLimit,
    'outTimeLimit': outTimeLimit,
    'lateTimeLimit': lateTimeLimit,
    'earlyExitTimeLimit': earlyExitTimeLimit,
    'lateDeductionRate': lateDeductionRate,
    'earlyExitDeductionRate': earlyExitDeductionRate,
    'allowedLeaves': allowedLeaves,
    'joiningDate': joiningDate,
    'biometricPin': biometricPin,
  };

  // Helper to support Map-like access if needed, though better to use properties
  dynamic operator [](String key) {
    switch (key) {
      case 'id': return id;
      case 'name': return name;
      case 'role': return role;
      case 'phone': return phone;
      case 'salonId': return salonId;
      case 'userId': return userId;
      case 'salaryType': return salaryType;
      case 'salaryValue': return salaryValue;
      case 'commissionPercentage': return commissionPercentage;
      case 'balance': return balance;
      case 'user': return user;
      case 'createdAt': return createdAt;
      case 'inTimeLimit': return inTimeLimit;
      case 'outTimeLimit': return outTimeLimit;
      case 'lateTimeLimit': return lateTimeLimit;
      case 'earlyExitTimeLimit': return earlyExitTimeLimit;
      case 'lateDeductionRate': return lateDeductionRate;
      case 'earlyExitDeductionRate': return earlyExitDeductionRate;
      case 'allowedLeaves': return allowedLeaves;
      case 'joiningDate': return joiningDate;
      case 'biometricPin': return biometricPin;
      default: return null;
    }
  }
}
