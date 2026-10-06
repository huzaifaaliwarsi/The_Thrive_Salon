class Sale {
  final String id;
  final String? customerPhone;
  final String? customerName;
  final String? customerSource;
  final double subtotal;
  final double discount;
  final double total;
  final double taxRate;
  final double taxAmount;
  final String paymentMethod;
  final String? staffId;
  final DateTime createdAt;
  final List<SaleItem> items;
  final bool isSynced;
  final String? status; // ACTIVE, VOID, or DRAFT
  final double? commissionRate;
  final double? amountPaid;

  Sale({
    required this.id,
    this.customerPhone,
    this.customerName,
    this.customerSource,
    this.subtotal = 0.0,
    this.discount = 0.0,
    required this.total,
    this.taxRate = 0.0,
    this.taxAmount = 0.0,
    required this.paymentMethod,
    this.staffId,
    required this.createdAt,
    required this.items,
    this.isSynced = false,
    this.status = 'ACTIVE',
    this.commissionRate,
    this.amountPaid,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'],
      customerPhone: json['customerPhone'] ?? json['clientPhone'],
      customerName: json['customerName'] ?? json['clientName'],
      customerSource: json['customerSource'],
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0,
      discount: double.tryParse(json['discount']?.toString() ?? '0') ?? 0.0,
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      taxRate: double.tryParse(json['taxRate']?.toString() ?? '0') ?? 0.0,
      taxAmount: double.tryParse(json['taxAmount']?.toString() ?? '0') ?? 0.0,
      paymentMethod: json['paymentMethod'] ?? 'CASH',
      staffId: json['staffId'],
      status: json['status'] ?? 'ACTIVE',
      commissionRate: double.tryParse(json['commissionRate']?.toString() ?? '0'),
      amountPaid: json['amountPaid'] != null ? double.tryParse(json['amountPaid'].toString()) : null,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      items: (json['items'] as List?)?.map((i) => SaleItem.fromJson(i)).toList() ?? 
             (json['saleItems'] as List?)?.map((i) => SaleItem.fromJson(i)).toList() ?? [],
      isSynced: json['isSynced'] == 1 || json['isSynced'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerPhone': customerPhone,
    'customerName': customerName,
    'customerSource': customerSource,
    'subtotal': subtotal,
    'discount': discount,
    'total': total,
    'taxRate': taxRate,
    'taxAmount': taxAmount,
    'paymentMethod': paymentMethod,
    'staffId': staffId,
    'status': status,
    'commissionRate': commissionRate,
    'amountPaid': amountPaid,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
  };

  Map<String, dynamic> toDb() => {
    'id': id,
    'totalAmount': total.toString(),
    'paymentMethod': paymentMethod,
    'clientPhone': customerPhone,
    'clientName': customerName,
    'staffId': staffId,
    'status': status,
    'commissionRate': commissionRate?.toString(),
    'amountPaid': amountPaid?.toString(),
    'createdAt': createdAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
  };
}

class SaleItem {
  final String? id;
  final String serviceId;
  final String? serviceName;
  final double price;
  final int quantity;
  final bool isInternal;
  final String? staffId;

  SaleItem({
    this.id,
    required this.serviceId,
    this.serviceName,
    required this.price,
    required this.quantity,
    this.isInternal = false,
    this.staffId,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    final resolvedServiceId = json['productId'] != null
        ? 'inv_${json['productId']}'
        : (json['serviceId']?.toString() ?? '');
    final resolvedServiceName = json['serviceName'] ?? json['service']?['name'] ?? json['product']?['name'] ?? json['inventoryItem']?['name'] ?? 'Unknown Item';

    return SaleItem(
      id: json['id'],
      serviceId: resolvedServiceId,
      serviceName: resolvedServiceName,
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      quantity: json['quantity'] is int 
          ? json['quantity'] 
          : (int.tryParse(json['quantity']?.toString() ?? '1') ?? (double.tryParse(json['quantity']?.toString() ?? '1')?.toInt() ?? 1)),
      isInternal: json['isInternal'] == true || json['isInternal'] == 1 || json['isInternal'] == 'true',
      staffId: json['staffId'],
    );
  }

  Map<String, dynamic> toJson() => {
    'serviceId': serviceId,
    'price': price,
    'quantity': quantity,
    'isInternal': isInternal,
    'staffId': staffId,
  };

  Map<String, dynamic> toDb(String saleId) => {
    'id': id ?? '',
    'saleId': saleId,
    'serviceId': serviceId,
    'serviceName': serviceName,
    'price': price.toString(),
    'quantity': quantity,
  };
}
