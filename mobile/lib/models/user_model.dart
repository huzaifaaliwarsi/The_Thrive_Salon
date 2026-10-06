class User {
  final String id;
  final String email;
  final String role;
  final String? salonId;

  User({
    required this.id,
    required this.email,
    required this.role,
    this.salonId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      role: json['role'],
      salonId: json['salonId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'salonId': salonId,
    };
  }
}

class Salon {
  final String id;
  final String name;
  final String? logo;
  final String? address;

  Salon({
    required this.id,
    required this.name,
    this.logo,
    this.address,
  });

  factory Salon.fromJson(Map<String, dynamic> json) {
    return Salon(
      id: json['id'],
      name: json['name'],
      logo: json['logo'],
      address: json['address'],
    );
  }
}
