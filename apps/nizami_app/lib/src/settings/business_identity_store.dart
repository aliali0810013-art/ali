import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BusinessIdentityStore extends ChangeNotifier {
  BusinessIdentityStore._();

  static final instance = BusinessIdentityStore._();
  static const _storageKey = 'ninesoft.branch_business_profiles.v1';

  final Map<String, BranchBusinessProfile> _profiles = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final item in decoded) {
        final profile = BranchBusinessProfile.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        _profiles[profile.storageKey] = profile;
      }
    } catch (_) {
      // A damaged local preference must not prevent the accounting app opening.
    }
  }

  BranchBusinessProfile profileFor(
    String branchId,
    String tenantScope, {
    String? displayName,
  }) {
    return _profiles.putIfAbsent(
      BranchBusinessProfile.makeStorageKey(tenantScope, branchId),
      () => BranchBusinessProfile(
        tenantScope: tenantScope,
        branchId: branchId,
        businessName: displayName ?? tenantScope,
      ),
    );
  }

  void save(BranchBusinessProfile profile) {
    _profiles[profile.storageKey] = profile;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _storageKey,
        jsonEncode(
          _profiles.values.map((profile) => profile.toJson()).toList(),
        ),
      );
    } catch (_) {
      // Keep the in-memory setting usable when platform storage is unavailable.
    }
  }
}

class BranchBusinessProfile {
  const BranchBusinessProfile({
    this.tenantScope = '',
    required this.branchId,
    required this.businessName,
    this.businessNameEn = '',
    this.tagline = '',
    this.phone = '',
    this.address = '',
    this.email = '',
    this.header = '',
    this.footer = 'شكرًا لتعاملكم معنا',
    this.whatsappNumber = '',
    this.primaryColorValue = 0xFF123E78,
    this.logoScale = 1.0,
    this.logoBytes,
  });

  final String tenantScope;
  final String branchId;
  final String businessName;
  final String businessNameEn;
  final String tagline;
  final String phone;
  final String address;
  final String email;
  final String header;
  final String footer;
  final String whatsappNumber;
  final int primaryColorValue;
  final double logoScale;
  final Uint8List? logoBytes;

  Color get primaryColor => Color(primaryColorValue);

  String get storageKey => makeStorageKey(tenantScope, branchId);

  static String makeStorageKey(String tenantScope, String branchId) =>
      '$tenantScope::$branchId';

  factory BranchBusinessProfile.fromJson(Map<String, dynamic> json) {
    final logo = json['logo'] as String?;
    return BranchBusinessProfile(
      tenantScope: json['tenantScope'] as String? ?? '',
      branchId: json['branchId'] as String? ?? 'MAIN',
      businessName: json['businessName'] as String? ?? '',
      businessNameEn: json['businessNameEn'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      email: json['email'] as String? ?? '',
      header: json['header'] as String? ?? '',
      footer: json['footer'] as String? ?? 'شكرًا لتعاملكم معنا',
      whatsappNumber: json['whatsappNumber'] as String? ?? '',
      primaryColorValue:
          (json['primaryColorValue'] as num?)?.toInt() ?? 0xFF123E78,
      logoScale: (json['logoScale'] as num?)?.toDouble() ?? 1.0,
      logoBytes: logo == null || logo.isEmpty ? null : base64Decode(logo),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenantScope': tenantScope,
    'branchId': branchId,
    'businessName': businessName,
    'businessNameEn': businessNameEn,
    'tagline': tagline,
    'phone': phone,
    'address': address,
    'email': email,
    'header': header,
    'footer': footer,
    'whatsappNumber': whatsappNumber,
    'primaryColorValue': primaryColorValue,
    'logoScale': logoScale,
    'logo': logoBytes == null ? null : base64Encode(logoBytes!),
  };

  BranchBusinessProfile copyWith({
    String? businessName,
    String? businessNameEn,
    String? tagline,
    String? phone,
    String? address,
    String? email,
    String? header,
    String? footer,
    String? whatsappNumber,
    int? primaryColorValue,
    double? logoScale,
    Uint8List? logoBytes,
    bool removeLogo = false,
  }) {
    return BranchBusinessProfile(
      tenantScope: tenantScope,
      branchId: branchId,
      businessName: businessName ?? this.businessName,
      businessNameEn: businessNameEn ?? this.businessNameEn,
      tagline: tagline ?? this.tagline,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      email: email ?? this.email,
      header: header ?? this.header,
      footer: footer ?? this.footer,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      logoScale: logoScale ?? this.logoScale,
      logoBytes: removeLogo ? null : logoBytes ?? this.logoBytes,
    );
  }
}
