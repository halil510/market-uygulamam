// lib/ekranlar/borc/borc_takip_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import '../../modeller/borc_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import 'widgets/borc_odeme_bottom_sheet.dart';

class BorcTakipEkrani extends ConsumerStatefulWidget {
  const BorcTakipEkrani({super.key});

  @override
  ConsumerState<BorcTakipEkrani> createState() => _BorcTakipEkraniState();
}

class _BorcTakipEkraniState extends ConsumerState<BorcTakipEkrani> {
  List<BorcModel> _filtreli = [];
  String _aktifFiltre = 'Tum';

  static const _filtreler = ['Tum', 'Kredi Kartı', 'Vergi', 'SGK', 'Kira', 'Fatura', 'Odenen'];

  @override
  void initState() {
    super.initState();
    _filtrele(null);
  }

  void _filtrele(List<BorcModel>? borclar) {
    final tum = borclar ?? [];
    final q = _aktifFiltre;
    setState(() {
      _filtreli = tum.where((b) {
        if (q == 'Tum') return true;
        if (q == 'Odenen') return b.odendi;
        return b.tur == _turMap(q) && !b.odendi;
      }).toList();
    });
  }

  String _turMap(String label) {
    switch (label) {
      case 'Kredi Kartı': return 'kredi_karti';
      case 'Vergi': return 'vergi';
      case 'SGK': return 'sgk';
      case 'Kira': return 'kira';
      case 'Fatura': return 'fatura';
      default: return '';
    }
  }

  String _turEtiket(String tur) {
    switch (tur) {
      case 'kredi_karti': return 'Kredi Kartı';
      case 'vergi': return 'Vergi';
      case 'sgk': return 'SGK';
      case 'kira': return 'Kira';
      case 'fatura': return 'Fatura';
      default: return tur;
    }
  }

  Color _turRenk(String tur) {
    switch (tur) {
      case 'kredi_karti': return Colors.blue.shade700;
      case 'vergi': return Colors.red.shade700;
      case 'sgk': return Colors.orange.shade700;
      case 'kira': return Colors.purple.shade700;
      case 'fatura': return Colors.teal.shade700;
      default: return context.textSecondary;
    }
  }

  IconData _turIkon(String tur) {
    switch (tur) {
      case 'kredi_karti': return Icons.credit_card;
      case 'vergi': return Icons.account_balance;
      case 'sgk': return Icons.health_and_safety;
      case 'kira': return Icons.home;
      case 'fatura': return Icons.receipt;
      default: return Icons.payment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borclarAsync = ref.watch(tumBorclarProvider);

    // Özet hesaplama
    double ozetToplam = 0;
    int gecikmis = 0;
    borclarAsync.whenData((liste) {
      ozetToplam = liste.fold<double>(0, (s, b) => s + (b.odendi ? 0 : b.kalanTutar));
      gecikmis = liste.where((b) => b.vadesiGecti && !b.odendi).length;
    });

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Borç Takip',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(tumBorclarProvider),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              final eklendi = await context.push<bool>('/borc-ekle');
              if (eklendi == true) ref.invalidate(tumBorclarProvider);
            },
          ),
        ],
      ),
      body: borclarAsync.when(
        loading: () => const TsYukleniyor(),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            Text('Hata: $e', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(tumBorclarProvider),
              child: const Text('Tekrar Dene'),
            ),
          ]),
        ),
        data: (borclar) {
          // Filtrele
          if (_filtreli.isEmpty && borclar.isNotEmpty) {
            _filtrele(borclar);
          }
          // Filtreleme sonrası güncelleme
          final gosterilecek = _filtreli;

          return Column(children: [
            // Özet kartlar
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TsRenk.kart(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8)],
              ),
              child: Row(children: [
                _ozetItem('Toplam Borç', ParaUtils.formatla(ozetToplam), Icons.payment, Colors.blue),
                const SizedBox(width: 12),
                _ozetItem('Gecikmiş', '$gecikmis', Icons.warning_amber, Colors.red),
                const SizedBox(width: 12),
                _ozetItem('Aktif', '${borclar.where((b) => !b.odendi).length}', Icons.pending, Colors.orange),
              ]),
            ),

            // Filtre
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: _filtreler.map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f),
                  selected: _aktifFiltre == f,
                  onSelected: (_) => setState(() { _aktifFiltre = f; _filtrele(borclar); }),
                  selectedColor: AppRenkler.primary,
                  labelStyle: TextStyle(color: _aktifFiltre == f ? Colors.white : context.textSecondary),
                ),
              )).toList()),
            ),

            // Liste
            Expanded(
              child: gosterilecek.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                        SizedBox(height: 12),
                        Text('Tüm borçlar ödenmiş!', style: TextStyle(color: context.textSecondary)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(tumBorclarProvider),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: gosterilecek.length,
                        itemBuilder: (_, i) => _BorcKarti(borc: gosterilecek[i]),
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _ozetItem(String label, String deger, IconData ikon, Color renk) => Expanded(
    child: Column(children: [
      Icon(ikon, color: renk, size: 20),
      const SizedBox(height: 4),
      Text(deger, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: renk)),
      Text(label, style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
    ]),
  );
}

// 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): bu kart, borç ödemesini
// BorcDeposu().odemeYap() ile DOĞRUDAN yapıyordu — bu, sadece borcun
// 'odenen_tutar'ını günceleyip sabit 'Nakit' etiketli bir geçmiş kaydı
// ekleyen ilkel bir katmandır; kasa/banka/kredi kartı hareketi ve Gider
// kaydı OLUŞTURMAZ (bkz. BorcOdemeIslemServisi — projedeki TEK doğru,
// eksiksiz akış). Ayrıca girilen tutarın kalan borcu AŞIP AŞMADIĞI HİÇ
// kontrol edilmiyordu. Sonuç: bu ekrandan yapılan HER ödeme kasa/banka
// bakiyesini kalıcı olarak yanlış bırakıyordu. Artık dashboard/detay
// ekranlarıyla AYNI paylaşılan, doğrulanmış BorcOdemeBottomSheet
// kullanılıyor — bu yüzden ConsumerWidget'a çevrildi (ref gerekiyor).
class _BorcKarti extends ConsumerWidget {
  final BorcModel borc;
  const _BorcKarti({required this.borc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renk = _turRenk(context, borc.tur);
    final vadesiGecti = borc.vadesiGecti;
    final kalanGun = borc.kalanGun;
    final kalanTutar = borc.kalanTutar;
    final odendi = borc.odendi;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: odendi ? context.borderColor : (vadesiGecti ? Colors.red.shade50 : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: vadesiGecti ? Colors.red.shade300 : (odendi ? TsRenk.ayirac(context) : renk.withAlpha(77)),
          width: vadesiGecti ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: renk.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_turIkon(borc.tur), color: renk, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(borc.baslik,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: odendi ? TsRenk.metinIkincil(context) : context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: renk.withAlpha(26),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_turEtiket(borc.tur),
                        style: TextStyle(fontSize: 10, color: renk, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.calendar_today, size: 12, color: TsRenk.metinIkincil(context)),
                  const SizedBox(width: 4),
                  Text('Kesim: ${DateFormat('dd.MM.yyyy').format(borc.kesimTarihi)}',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                  const SizedBox(width: 12),
                  Icon(Icons.event, size: 12, color: vadesiGecti ? Colors.red : TsRenk.metinIkincil(context)),
                  const SizedBox(width: 4),
                  Text(
                    'Son Ödeme: ${DateFormat('dd.MM.yyyy').format(borc.sonOdemeTarihi)}',
                    style: TextStyle(fontSize: 11, color: vadesiGecti ? Colors.red : TsRenk.metinIkincil(context)),
                  ),
                ]),
              ]),
            ),
            if (!odendi && vadesiGecti)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('GECİKTİ',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  odendi
                      ? 'Ödenmiştir'
                      : 'Kalan: ${ParaUtils.formatla(kalanTutar)} / ${ParaUtils.formatla(borc.tutar)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: odendi ? Colors.green : context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (!odendi) ...[
                  LinearProgressIndicator(
                    value: borc.odemeOrani / 100,
                    backgroundColor: TsRenk.ayirac(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      vadesiGecti ? Colors.red : renk,
                    ),
                    minHeight: 4,
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${borc.odemeOrani.toStringAsFixed(0)}% ödendi',
                        style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                    if (!odendi && kalanGun > 0 && kalanGun <= 7)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kalanGun <= 3 ? Colors.red.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$kalanGun gün kaldı',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: kalanGun <= 3 ? Colors.red : Colors.orange,
                            )),
                      ),
                  ]),
                ],
                if (borc.taksitSayisi > 1)
                  Text('${borc.odenenTaksit}/${borc.taksitSayisi} Taksit',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                if (borc.altTur != null)
                  Text(borc.altTur!,
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              ]),
            ),
            // Aksiyon butonları
            if (!odendi)
              FilledButton.icon(
                onPressed: () => _odemeYap(context, ref),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Ödeme'),
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppRenkler.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _odemeYap(BuildContext context, WidgetRef ref) async {
    final bankaHesaplari = await ref.read(bankaHesaplarProvider(null).future);
    final krediKartlari = await ref.read(krediKartlariProvider(null).future);
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BorcOdemeBottomSheet(
        borc: borc,
        bankaHesaplari: bankaHesaplari,
        krediKartlari: krediKartlari,
        onOdemeYapildi: () {
          ref.invalidate(tumBorclarProvider);
          BildirimServisi.basari(context, '${borc.baslik} için ödeme kaydedildi');
        },
      ),
    );
  }

  // context parametresi eklendi — _BorcKarti bir StatelessWidget;
  // yardımcı metotlarında context otomatik gelmez.
  Color _turRenk(BuildContext context, String tur) {
    switch (tur) {
      case 'kredi_karti': return Colors.blue.shade700;
      case 'vergi': return Colors.red.shade700;
      case 'sgk': return Colors.orange.shade700;
      case 'kira': return Colors.purple.shade700;
      case 'fatura': return Colors.teal.shade700;
      default: return context.textSecondary;
    }
  }

  IconData _turIkon(String tur) {
    switch (tur) {
      case 'kredi_karti': return Icons.credit_card;
      case 'vergi': return Icons.account_balance;
      case 'sgk': return Icons.health_and_safety;
      case 'kira': return Icons.home;
      case 'fatura': return Icons.receipt;
      default: return Icons.payment;
    }
  }

  String _turEtiket(String tur) {
    switch (tur) {
      case 'kredi_karti': return 'Kredi Kartı';
      case 'vergi': return 'Vergi';
      case 'sgk': return 'SGK';
      case 'kira': return 'Kira';
      case 'fatura': return 'Fatura';
      default: return tur;
    }
  }
}