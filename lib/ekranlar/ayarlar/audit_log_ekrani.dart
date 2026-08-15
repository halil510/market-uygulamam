// lib/ekranlar/ayarlar/audit_log_ekrani.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/audit_log_servisi.dart';

class AuditLogEkrani extends StatefulWidget {
  const AuditLogEkrani({super.key});

  @override
  State<AuditLogEkrani> createState() => _AuditLogEkraniState();
}

class _AuditLogEkraniState extends State<AuditLogEkrani> {
  List<Map<String, dynamic>> _kayitlar = [];
  bool _yukleniyor = true;
  String? _tabloFiltre;

  static const _tabloEtiketleri = {
    'urunler': 'Ürünler', 'cari': 'Cari', 'satislar': 'Satışlar',
    'faturalar': 'Faturalar', 'promosyonlar': 'Promosyonlar',
    'masalar': 'Masalar', 'borclar': 'Borçlar', 'kullanicilar': 'Kullanıcılar',
    'kasa_hareketleri': 'Kasa', 'stok_hareket': 'Stok',
  };

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final liste = await AuditLogServisi().gunlukGetir(tabloFiltre: _tabloFiltre);
      if (!mounted) return;
      setState(() { _kayitlar = liste; _yukleniyor = false; });
    } catch (e) {
      // 🔴 DÜZELTME: Bu fonksiyonda hiç try-catch yoktu — servis hata
      // verirse _yukleniyor hiçbir zaman false olmuyordu, ekran
      // sonsuza kadar "yükleniyor" durumunda kalıyordu.
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  (IconData, Color) _islemGorseli(String tur) {
    switch (tur) {
      case 'Silme':
        return (Icons.delete_outline, Colors.red);
      case 'İptal':
        return (Icons.cancel_outlined, Colors.orange);
      default:
        return (Icons.edit_outlined, context.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'İşlem Geçmişi (Audit Log)',
        aksiyonlar: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) { setState(() => _tabloFiltre = v); _yukle(); },
            itemBuilder: (c) => [
              const PopupMenuItem(value: null, child: Text('Tümü')),
              ..._tabloEtiketleri.entries.map(
                  (e) => PopupMenuItem(value: e.key, child: Text(e.value))),
            ],
          ),
        ],
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _kayitlar.isEmpty
              ? Center(child: Text('Henüz kayıtlı işlem yok.',
                  style: TextStyle(color: context.textHint)))
              : RefreshIndicator(
                  onRefresh: _yukle,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _kayitlar.length,
                    itemBuilder: (c, i) {
                      final k = _kayitlar[i];
                      final tur = k['islem_turu'] as String? ?? '';
                      final (ikon, renk) = _islemGorseli(tur);
                      final tarih = DateTime.tryParse(k['tarih']?.toString() ?? '');
                      final tabloEtiket = _tabloEtiketleri[k['tablo_adi']] ?? k['tablo_adi'] ?? '';
                      final ozet = k['ozet'] as String?;
                      final kullanici = k['kullanici_adi'] as String? ?? 'Bilinmiyor';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: renk.withAlpha(30), shape: BoxShape.circle),
                            child: Icon(ikon, size: 18, color: renk),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(tabloEtiket, style: TextStyle(fontWeight: FontWeight.w700,
                                    fontSize: 13, color: context.textPrimary)),
                                const SizedBox(width: 6),
                                Text('· $tur', style: TextStyle(fontSize: 12, color: renk)),
                              ]),
                              if (ozet != null && ozet.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(ozet, style: TextStyle(fontSize: 13, color: context.textSecondary)),
                                ),
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.person_outline, size: 12, color: context.textHint),
                                const SizedBox(width: 3),
                                Text(kullanici, style: TextStyle(fontSize: 11, color: context.textHint)),
                                const SizedBox(width: 10),
                                Icon(Icons.access_time, size: 12, color: context.textHint),
                                const SizedBox(width: 3),
                                Text(
                                  tarih != null ? DateFormat('dd.MM.yyyy HH:mm').format(tarih) : '',
                                  style: TextStyle(fontSize: 11, color: context.textHint),
                                ),
                              ]),
                            ]),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
