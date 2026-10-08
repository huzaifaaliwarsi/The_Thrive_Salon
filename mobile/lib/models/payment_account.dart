class PaymentAccount {
  final String id;
  final String salonId;
  final String accountName;
  final String? accountTitle;
  final String? accountNumber;
  final String? iban;
  final String type;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PaymentAccount({
    required this.id,
    required this.salonId,
    required this.accountName,
    this.accountTitle,
    this.accountNumber,
    this.iban,
    this.type = 'BANK',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory PaymentAccount.fromJson(Map<String, dynamic> json) {
    return PaymentAccount(
      id: json['id']?.toString() ?? '',
      salonId: json['salonId']?.toString() ?? '',
      accountName: json['accountName']?.toString() ?? '',
      accountTitle: json['accountTitle']?.toString(),
      accountNumber: json['accountNumber']?.toString(),
      iban: json['iban']?.toString(),
      type: json['type']?.toString() ?? 'BANK',
      isActive: json['isActive'] == true || json['isActive'] == 'true' || json['isActive'] == 1,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'salonId': salonId,
      'accountName': accountName,
      'accountTitle': accountTitle,
      'accountNumber': accountNumber,
      'iban': iban,
      'type': type,
      'isActive': isActive,
    };
  }

  PaymentAccount copyWith({
    String? id,
    String? salonId,
    String? accountName,
    String? accountTitle,
    String? accountNumber,
    String? iban,
    String? type,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentAccount(
      id: id ?? this.id,
      salonId: salonId ?? this.salonId,
      accountName: accountName ?? this.accountName,
      accountTitle: accountTitle ?? this.accountTitle,
      accountNumber: accountNumber ?? this.accountNumber,
      iban: iban ?? this.iban,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
