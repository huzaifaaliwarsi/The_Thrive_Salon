import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/service_model.dart';
import '../models/sale_model.dart';

class POSState {
  final List<SaleItem> cart;
  final String customerPhone;
  final String customerName;
  final String customerSource;
  final String selectedCategory;
  final String searchQuery;
  final String paymentMethod;
  final double? customCommissionRate;
  final double discountValue;
  final String discountType; // 'FLAT' or 'PERCENT'
  final double taxRate;
  final double? amountPaid;
  final bool isLoading;
  // Added to track service names for display in cart since SaleItem only has serviceId
  final Map<String, String> serviceNameMap; 
  final String? draftId;
  final String? appointmentId;
  final String? selectedStaffId;

  POSState({
    this.cart = const [],
    this.customerPhone = '',
    this.customerName = '',
    this.customerSource = 'WALK_IN',
    this.selectedCategory = 'All',
    this.searchQuery = '',
    this.paymentMethod = 'CASH',
    this.customCommissionRate,
    this.discountValue = 0,
    this.discountType = 'FLAT',
    this.taxRate = 0.0, // Default VAT 0%
    this.amountPaid,
    this.isLoading = false,
    this.serviceNameMap = const {},
    this.draftId,
    this.appointmentId,
    this.selectedStaffId,
  });

  double get subtotal => cart.fold(0, (sum, item) => sum + (item.isInternal ? 0.0 : (item.price * item.quantity)));

  double get discount {
    if (discountType == 'PERCENT') {
      return (subtotal * (discountValue / 100.0)).clamp(0.0, subtotal);
    }
    return discountValue.clamp(0.0, subtotal);
  }

  double get taxAmount {
    final base = subtotal - discount;
    return (base < 0 ? 0.0 : base) * (taxRate / 100);
  }

  double get total {
    final base = subtotal - discount;
    final baseClamped = base < 0 ? 0.0 : base;
    return baseClamped + taxAmount;
  }

  POSState copyWith({
    List<SaleItem>? cart,
    String? customerPhone,
    String? customerName,
    String? customerSource,
    String? selectedCategory,
    String? searchQuery,
    String? paymentMethod,
    double? customCommissionRate,
    double? discountValue,
    String? discountType,
    double? taxRate,
    double? amountPaid,
    bool? isLoading,
    Map<String, String>? serviceNameMap,
    String? draftId,
    String? appointmentId,
    String? selectedStaffId,
  }) {
    return POSState(
      cart: cart ?? this.cart,
      customerPhone: customerPhone ?? this.customerPhone,
      customerName: customerName ?? this.customerName,
      customerSource: customerSource ?? this.customerSource,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      customCommissionRate: customCommissionRate ?? this.customCommissionRate,
      discountValue: discountValue ?? this.discountValue,
      discountType: discountType ?? this.discountType,
      taxRate: taxRate ?? this.taxRate,
      amountPaid: amountPaid ?? this.amountPaid,
      isLoading: isLoading ?? this.isLoading,
      serviceNameMap: serviceNameMap ?? this.serviceNameMap,
      draftId: draftId ?? this.draftId,
      appointmentId: appointmentId ?? this.appointmentId,
      selectedStaffId: selectedStaffId ?? this.selectedStaffId,
    );
  }
}

class POSNotifier extends StateNotifier<POSState> {
  POSNotifier() : super(POSState());

  void addToCart(Service service) {
    if (service.isPackage && service.bundledServices != null && service.bundledServices!.isNotEmpty) {
      for (final bundledService in service.bundledServices!) {
        _addSingleItem(bundledService);
      }
    } else {
      _addSingleItem(service);
    }
  }

  void addCustomPackageToCart(Service packageService, List<Service> customItems, double packagePrice) {
    final cart = List<SaleItem>.from(state.cart);
    final newMap = Map<String, String>.from(state.serviceNameMap);
    
    // Add as a combined package line item or individual custom items
    final itemNames = customItems.map((s) => s.name).join(', ');
    final pName = '${packageService.name} ($itemNames)';
    newMap[packageService.id] = pName;

    cart.add(SaleItem(
      serviceId: packageService.id,
      serviceName: pName,
      price: packagePrice,
      quantity: 1,
      staffId: null,
    ));

    state = state.copyWith(cart: cart, serviceNameMap: newMap);
  }

  void _addSingleItem(Service service) {
    final cart = List<SaleItem>.from(state.cart);
    // Group by both serviceId and null staffId so different staff get different line items
    final index = cart.indexWhere((item) => item.serviceId == service.id && item.staffId == null);
    
    final newMap = Map<String, String>.from(state.serviceNameMap);
    newMap[service.id] = service.name;

    if (index >= 0) {
      cart[index] = SaleItem(
        serviceId: cart[index].serviceId,
        serviceName: service.name,
        price: cart[index].price,
        quantity: cart[index].quantity + 1,
        staffId: cart[index].staffId,
        isInternal: cart[index].isInternal,
      );
    } else {
      cart.add(SaleItem(
        serviceId: service.id,
        serviceName: service.name,
        price: double.parse(service.price),
        quantity: 1,
        staffId: null, // Initialize with no staff
      ));
    }
    state = state.copyWith(cart: cart, serviceNameMap: newMap);
  }

  void updateQuantity(int index, int delta) {
    final cart = List<SaleItem>.from(state.cart);
    final item = cart[index];
    final newQty = item.quantity + delta;
    
    if (newQty <= 0) {
      cart.removeAt(index);
    } else {
      cart[index] = SaleItem(
        serviceId: item.serviceId,
        serviceName: item.serviceName,
        price: item.price,
        quantity: newQty,
        isInternal: item.isInternal,
        staffId: item.staffId,
      );
    }
    state = state.copyWith(cart: cart);
  }

  void toggleInternalUse(int index, Service service) {
    final cart = List<SaleItem>.from(state.cart);
    final item = cart[index];
    final newIsInternal = !item.isInternal;
    
    double newPrice = double.parse(service.price);
    if (newIsInternal && service.costPrice != null) {
      newPrice = double.parse(service.costPrice!);
    }

    cart[index] = SaleItem(
      serviceId: item.serviceId,
      serviceName: item.serviceName,
      price: newPrice,
      quantity: item.quantity,
      isInternal: newIsInternal,
      staffId: item.staffId,
    );
    state = state.copyWith(cart: cart);
  }

  void setItemStaff(int index, String? staffId) {
    final cart = List<SaleItem>.from(state.cart);
    final item = cart[index];
    cart[index] = SaleItem(
      serviceId: item.serviceId,
      serviceName: item.serviceName,
      price: item.price,
      quantity: item.quantity,
      isInternal: item.isInternal,
      staffId: staffId,
    );
    state = state.copyWith(cart: cart);
  }

  void setCategory(String category) => state = state.copyWith(selectedCategory: category);
  void setSearch(String query) => state = state.copyWith(searchQuery: query);
  void setPaymentMethod(String method) => state = state.copyWith(paymentMethod: method);
  void setCustomerPhone(String phone) => state = state.copyWith(customerPhone: phone);
  void setCustomerName(String name) => state = state.copyWith(customerName: name);
  void setCustomerSource(String source) => state = state.copyWith(customerSource: source);
  void setDiscount(double discount) => state = state.copyWith(discountValue: discount < 0 ? 0.0 : discount);
  void setDiscountType(String type) => state = state.copyWith(discountType: type);
  void setTaxRate(double rate) => state = state.copyWith(taxRate: rate < 0 ? 0.0 : rate);
  void setCommissionRate(double? rate) => state = state.copyWith(customCommissionRate: (rate != null && rate < 0) ? 0.0 : rate);
  void setAmountPaid(double? amount) => state = state.copyWith(amountPaid: (amount != null && amount < 0) ? 0.0 : amount);
  void setLoading(bool loading) => state = state.copyWith(isLoading: loading);
  void setDraftId(String? id) => state = state.copyWith(draftId: id);
  void setAppointmentId(String? id) => state = state.copyWith(appointmentId: id);

  String getOrGenerateDraftId() {
    if (state.draftId != null && state.draftId!.isNotEmpty) {
      return state.draftId!;
    }
    final newId = const Uuid().v4();
    state = state.copyWith(draftId: newId);
    return newId;
  }

  void loadDraft(Sale draft, Map<String, String> serviceNames) {
    state = POSState(
      cart: draft.items,
      customerPhone: draft.customerPhone ?? '',
      customerName: draft.customerName ?? '',
      customerSource: draft.customerSource ?? 'WALK_IN',
      paymentMethod: draft.paymentMethod,
      discountValue: draft.discount,
      discountType: 'FLAT',
      taxRate: draft.taxRate,
      amountPaid: draft.amountPaid,
      serviceNameMap: serviceNames,
      draftId: draft.id,
    );
  }

  void loadAppointment(dynamic appointment) {
    final List<dynamic> services = appointment['services'] ?? [];
    final List<SaleItem> cart = [];
    final newMap = <String, String>{};
    
    Map<String, String?> serviceStaffMap = {};
    if (appointment['serviceDetails'] != null) {
      try {
        final List<dynamic> details = jsonDecode(appointment['serviceDetails']);
        for (var item in details) {
          serviceStaffMap[item['serviceId'].toString()] = item['staffId']?.toString();
        }
      } catch (_) {}
    }

    if (services.isNotEmpty) {
      for (var s in services) {
        final id = s['id']?.toString() ?? '';
        final name = s['name']?.toString() ?? 'Service';
        final price = double.tryParse(s['price']?.toString() ?? '0') ?? 0.0;

        cart.add(SaleItem(
          serviceId: id,
          serviceName: name,
          price: price,
          quantity: 1,
          staffId: serviceStaffMap[id],
        ));
        newMap[id] = name;
      }
    } else if (appointment['service'] != null) {
      final s = appointment['service'];
      final id = s['id']?.toString() ?? '';
      final name = s['name']?.toString() ?? 'Service';
      final price = double.tryParse(s['price']?.toString() ?? '0') ?? 0.0;

      cart.add(SaleItem(
        serviceId: id,
        serviceName: name,
        price: price,
        quantity: 1,
        staffId: serviceStaffMap[id],
      ));
      newMap[id] = name;
    }

    state = POSState(
      cart: cart,
      customerName: appointment['customerName'] ?? '',
      customerPhone: appointment['customerPhone'] ?? '',
      serviceNameMap: newMap,
      paymentMethod: 'CASH',
      taxRate: 0.0,
      appointmentId: appointment['id']?.toString(),
    );
  }

  void clear() => state = POSState(taxRate: 0.0);
}

final posProvider = StateNotifierProvider<POSNotifier, POSState>((ref) => POSNotifier());
