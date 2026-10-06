class Service {
  final String id;
  final String name;
  final String price;
  final String category;
  final int duration;
  final String? salonId;
  final bool isPackage;
  final List<Service>? bundledServices;
  final String? costPrice;
  final String? description;
  final double? stockQuantity;
  final String? arabicName;

  Service({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.duration,
    this.salonId,
    this.isPackage = false,
    this.bundledServices,
    this.costPrice,
    this.description,
    this.stockQuantity,
    this.arabicName,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'].toString(),
      name: json['name'],
      price: json['price'].toString(),
      category: json['category'],
      duration: json['duration'] ?? 0,
      salonId: json['salonId'],
      isPackage: json['isPackage'] == 'true' || json['isPackage'] == true,
      bundledServices: json['bundleItems'] != null 
          ? (json['bundleItems'] as List).map((i) {
              final baseService = Service.fromJson(i['service']);
              return baseService.copyWith(
                price: i['price']?.toString() ?? baseService.price,
              );
            }).toList()
          : null,
      costPrice: json['unitPrice']?.toString() ?? json['costPrice']?.toString(),
      description: json['description'],
      stockQuantity: json['stockQuantity'] != null ? double.tryParse(json['stockQuantity'].toString()) : null,
      arabicName: json['arabicName'],
    );
  }

  Service copyWith({
    String? id,
    String? name,
    String? price,
    String? category,
    int? duration,
    String? salonId,
    bool? isPackage,
    List<Service>? bundledServices,
    String? costPrice,
    String? description,
    double? stockQuantity,
    String? arabicName,
  }) {
    return Service(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      duration: duration ?? this.duration,
      salonId: salonId ?? this.salonId,
      isPackage: isPackage ?? this.isPackage,
      bundledServices: bundledServices ?? this.bundledServices,
      costPrice: costPrice ?? this.costPrice,
      description: description ?? this.description,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      arabicName: arabicName ?? this.arabicName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'duration': duration,
    'salonId': salonId,
    'isPackage': isPackage,
    'bundledServices': bundledServices?.map((s) => {
      'serviceId': s.id,
      'price': s.price,
    }).toList(),
    'costPrice': costPrice,
    'description': description,
    'stockQuantity': stockQuantity,
    'arabicName': arabicName,
  };

  Map<String, dynamic> toDb() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'duration': duration,
    'salonId': salonId,
  };
}
