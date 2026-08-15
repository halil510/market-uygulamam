// lib/modeller/rezervasyon_model.dart
import 'package:flutter/material.dart';

class RezervasyonModel {
  final int? id;
  final String? globalId;
  final int masaId;
  final String masaAdi;
  final String musteriAdi;
  final String telefon;
  final int kisiSayisi;
  final DateTime tarih;
  final DateTime saat;
  final String? not_;
  final RezervasyonDurum durum;
  final DateTime? olusturmaTarihi;
  final int? kullaniciId;

  const RezervasyonModel({
    this.id,
    this.globalId,
    required this.masaId,
    this.masaAdi = '',
    required this.musteriAdi,
    required this.telefon,
    this.kisiSayisi = 2,
    required this.tarih,
    required this.saat,
    this.not_,
    this.durum = RezervasyonDurum.beklemede,
    this.olusturmaTarihi,
    this.kullaniciId,
  });

  bool get geldiMi => durum == RezervasyonDurum.geldi;
  bool get iptalMi => durum == RezervasyonDurum.iptal;

  factory RezervasyonModel.fromMap(Map<String, dynamic> m) => RezervasyonModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    masaId: m['masa_id'] as int,
    masaAdi: m['masa_adi'] as String? ?? '',
    musteriAdi: m['musteri_adi'] as String? ?? '',
    telefon: m['telefon'] as String? ?? '',
    kisiSayisi: (m['kisi_sayisi'] as int?) ?? 2,
    tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
    saat: DateTime.tryParse(m['saat']?.toString() ?? '') ?? DateTime.now(),
    not_: m['not_'] as String?,
    durum: RezervasyonDurum.values.firstWhere(
      (e) => e.name == m['durum'],
      orElse: () => RezervasyonDurum.beklemede,
    ),
    olusturmaTarihi: m['created_at'] != null 
        ? DateTime.tryParse(m['created_at'].toString()) 
        : null,
    kullaniciId: m['kullanici_id'] as int?,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'masa_id': masaId,
    'musteri_adi': musteriAdi,
    'telefon': telefon,
    'kisi_sayisi': kisiSayisi,
    'tarih': tarih.toIso8601String(),
    'saat': saat.toIso8601String(),
    if (not_ != null) 'not_': not_,
    'durum': durum.name,
    if (kullaniciId != null) 'kullanici_id': kullaniciId,
    'created_at': olusturmaTarihi?.toIso8601String() ?? DateTime.now().toIso8601String(),
  };
}

enum RezervasyonDurum {
  beklemede,
  onaylandi,
  geldi,
  iptal,
  tamamlandi,
}

extension RezervasyonDurumExt on RezervasyonDurum {
  String get label {
    switch (this) {
      case RezervasyonDurum.beklemede: return 'Beklemede';
      case RezervasyonDurum.onaylandi: return 'Onaylandı';
      case RezervasyonDurum.geldi: return 'Geldi';
      case RezervasyonDurum.iptal: return 'İptal';
      case RezervasyonDurum.tamamlandi: return 'Tamamlandı';
    }
  }

  Color get renk {
    switch (this) {
      case RezervasyonDurum.beklemede: return const Color(0xFFFF9800);
      case RezervasyonDurum.onaylandi: return const Color(0xFF2196F3);
      case RezervasyonDurum.geldi: return const Color(0xFF4CAF50);
      case RezervasyonDurum.iptal: return const Color(0xFFF44336);
      case RezervasyonDurum.tamamlandi: return const Color(0xFF9E9E9E);
    }
  }

  IconData get ikon {
    switch (this) {
      case RezervasyonDurum.beklemede: return Icons.schedule;
      case RezervasyonDurum.onaylandi: return Icons.check_circle_outline;
      case RezervasyonDurum.geldi: return Icons.check_circle;
      case RezervasyonDurum.iptal: return Icons.cancel;
      case RezervasyonDurum.tamamlandi: return Icons.done_all;
    }
  }
}