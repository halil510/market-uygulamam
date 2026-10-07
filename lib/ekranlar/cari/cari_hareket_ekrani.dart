// lib/ekranlar/cari/cari_hareket_ekrani.dart
import '../../cekirdek/utils/denetleyici_birak.dart';
import '../../cekirdek/utils/dosya_paylasim.dart';
import 'package:market_plus/servisler/pdf_font_servisi.dart';
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/satis_iptal_servisi.dart';
import '../../servisler/alim_islem_servisi.dart';
import '../../servisler/iade_islem_servisi.dart';
import '../../depolar/iade_deposu.dart';
import '../../saglayicilar/riverpod/satis_provider.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/tarih_utils.dart';
import '../../cekirdek/utils/excel_guvenlik_utils.dart';
import 'fis_detay_ekrani.dart';
import 'cari_detay_ekrani.dart' show cariHareketleriniGrupla;
import '../../widgetlar/ortak/fis_fiyat_guncelle_akisi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';

part 'cari_hareket_islemleri.dart';
part 'cari_hareket_disa_aktar.dart';

class CariHareketEkrani extends ConsumerStatefulWidget {
  final int cariId;
  const CariHareketEkrani({super.key, required this.cariId});
  @override
  ConsumerState<CariHareketEkrani> createState() => _CariHareketEkraniState();
}

class _CariHareketEkraniState extends ConsumerState<CariHareketEkrani> {
  final _depo = CariDeposu();
  final _fmt = DateFormat('dd.MM.yyyy');
  final _fmtT = DateFormat('dd.MM.yyyy HH:mm');

  CariModel? _cari;
  // Çoklu fiş seçimi (uzun bas) — "Son fiyata göre güncelle" için.
  final Set<int> _secimIdleri = {};
  List<CariHareketModel> _tumHareketler = [];
  List<CariHareketModel> _filtreli = [];
  bool _yukleniyor = true;
  String? _filtreTip;
  DateTimeRange? _tarihAralik;
  double _toplamBorc = 0, _toplamAlacak = 0, _bakiye = 0;
  /// Tarih aralığı seçiliyken aralık başından ÖNCEKİ bakiye (ekstre).
  double _devreden = 0;
  /// Tür filtresi varken "bakiye" anlamlı değildir — yalnızca listelenen
  /// hareketlerin neti gösterilir.
  bool get _turFiltreli => _filtreTip != null;
  /// Ekstre (PDF/Excel/CSV) yürüyen bakiyesinin başlangıcı: tarih aralığında
  /// devreden, filtre yokken cari bakiyesi − listenin neti (5000 kayıt
  /// tavanını aşan caride listeden önceki kısım), tür filtresinde 0.
  double get _ekstreBaslangic =>
      _turFiltreli ? 0.0 : _bakiye - (_toplamBorc - _toplamAlacak);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _secilenleriFiyatGuncelle() async {
    final ids = _tumHareketler
        .where((h) =>
            h.id != null &&
            _secimIdleri.contains(h.id) &&
            h.fisTipi == 'Satış' &&
            h.fisId != null)
        .map((h) => h.fisId!)
        .toList();
    final guncellendi = await fisFiyatGuncelleAkisi(context, ids,
        kullanici: ref.read(authProvider).kullanici?.adSoyad);
    if (!guncellendi || !mounted) return;
    setState(() => _secimIdleri.clear());
    ref.invalidate(cariDetayProvider(widget.cariId));
    ref.read(carilerProvider.notifier).yukle();
    await _yukle();
  }

  /// Sadece satış fişleri ('Satış' + fis_id) seçilebilir.
  void _secimDegistir(CariHareketModel h) {
    if (h.id == null) return;
    if (h.fisTipi != 'Satış' || h.fisId == null) {
      BildirimServisi.hata(context, 'Sadece satış fişleri seçilebilir');
      return;
    }
    setState(() {
      if (!_secimIdleri.remove(h.id)) _secimIdleri.add(h.id!);
    });
  }

  Color _bakiyeRenk() {
    if (_bakiye == 0) return context.textSecondary;
    final musteri = _cari?.cariTipi == 'Müşteri' ||
        _cari?.cariTipi == 'Hem Müşteri Hem Tedarikçi';
    if (musteri) {
      return _bakiye > 0 ? Colors.green.shade700 : Colors.blue.shade700;
    } else {
      return _bakiye < 0 ? Colors.red.shade700 : Colors.blue.shade700;
    }
  }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final cari = await _depo.idileGetir(widget.cariId);
      final hareketler = await _hareketleriGetir();
      await _devredenYukle();
      if (!mounted) return;
      setState(() {
        _cari = cari;
        _tumHareketler = hareketler;
        _filtrele();
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) {
        _yukleniyor = false;
        BildirimServisi.hata(context, 'Hata: $e');
      }
    }
  }

  // MASTER ERP DEEP AUDIT — Madde 25 (Performans) sertleştirmesi: bu
  // ekran ÖNCEDEN doğrudan Veritabani().db üzerinden 'SELECT * FROM
  // cari_hareket WHERE cari_id=? ...' çalıştırıyordu — hiç LIMIT yoktu.
  // Sıradan bir müşteride sorun olmaz ama yıllardır işlem gören bir
  // bayi/toptancı carisinde bu, TÜM geçmişi (potansiyel olarak on
  // binlerce satır) tek seferde belleğe çekip UI'yi kilitleyebilirdi.
  // Artık CariDeposu.hareketleriniGetir() üzerinden, yüksek ama GÜVENLİ
  // bir tavanla (5000) çağrılıyor — normal cariler için davranış
  // BİREBİR aynı (hemen hepsi 5000'in çok altında hareket sayısına
  // sahip), sadece patolojik uç durumda ekranı çökertmek yerine "son
  // 5000 hareket" gösterir. Ayrıca repository katmanını atlayan
  // doğrudan SQL erişimi de bu vesileyle kapatıldı.
  // 🔴 DÜZELTME (Cari/Fiş denetimi, 2026-09-20): Cari Detay ekranındaki
  // karma-ödeme çift-fiş-görünümü bug'ı (commit 7ac1d0a) sadece o
  // ekranda düzeltilmişti — AYNI ham veriyi gösteren bu "Tüm Hareketler"
  // ekranı (Cari Detay'daki FAB üzerinden erişilir) cariHareketleriniGrupla()'yı
  // hiç uygulamıyordu, yani karma ödemeli bir satış burada HÂLÂ 2 ayrı
  // "Satış" kartı olarak görünüyordu. Artık aynı gruplama burada da
  // uygulanıyor — _toplamBorc/_toplamAlacak (ve Excel/CSV/PDF export'ları)
  // de bu gruplanmış liste üzerinden hesaplandığı için, "Toplam Borç"
  // artık self-cancelling bilgi satırı yüzünden şişmiyor.
  Future<List<CariHareketModel>> _hareketleriGetir() async {
    final ham = await _depo.hareketleriniGetir(widget.cariId, limit: 5000);
    return cariHareketleriniGrupla(ham);
  }

  void _filtrele() {
    var list = List<CariHareketModel>.from(_tumHareketler);
    if (_filtreTip != null) {
      list = list.where((h) => h.fisTipi == _filtreTip).toList();
    }
    if (_tarihAralik != null) {
      // 🔴 DÜZELTME (2026-09-27): başlangıç ÖNCEDEN "start − 1 gün"den
      // sonrası alınıyordu — seçilen aralığın bir gün öncesi de listeye
      // (ve toplamlara/PDF ekstreye) giriyordu.
      final bas = _tarihAralik!.start;
      final bitis = _tarihAralik!.end.add(const Duration(days: 1));
      list = list
          .where((h) => !h.tarih.isBefore(bas) && h.tarih.isBefore(bitis))
          .toList();
    }
    _filtreli = list;
    _toplamBorc = ParaUtils.yuvarla(_filtreli.fold(0.0, (s, h) => s + h.borc));
    _toplamAlacak = ParaUtils.yuvarla(_filtreli.fold(0.0, (s, h) => s + h.alacak));
    // 🔴 DÜZELTME (2026-09-27): "Bakiye" ÖNCEDEN yalnızca listedeki
    // hareketlerin netiydi — tarih aralığı seçilince devreden bakiye
    // eklenmiyordu (müşteriye verilen PDF ekstre yanlış bakiye basıyordu);
    // filtre yokken de 5000 kayıt tavanını aşan caride eksik kalıyordu.
    // Artık: filtre yoksa kanonik cari bakiyesi; tarih aralığında
    // devreden + dönem neti; tür filtresinde yalnızca net.
    final net = _toplamBorc - _toplamAlacak;
    if (_turFiltreli) {
      _bakiye = net;
    } else if (_tarihAralik != null) {
      _bakiye = _devreden + net;
    } else {
      _bakiye = _cari?.bakiye ?? net;
    }
  }

  /// Tarih aralığı değişince devredeni SQL'den (limitsiz) yeniden hesaplar.
  Future<void> _devredenYukle() async {
    _devreden = _tarihAralik == null
        ? 0
        : await _depo.devredenBakiye(widget.cariId, _tarihAralik!.start);
  }

  Future<void> _tarihSec() async {
    try {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: TarihUtils.secimAraligiKirp(_tarihAralik, DateTime(2020),
            DateTime.now().add(const Duration(days: 1))),
      );
      if (r != null) {
        _tarihAralik = r;
        await _devredenYukle();
        if (mounted) setState(_filtrele);
      }
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Widget _bakiyeItem(String label, double val, Color renk) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 4),
      Text(ParaUtils.formatla(val),
          style: TextStyle(
              color: renk, fontSize: 14, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _tipChip(String label, String? tip) {
    return GestureDetector(
      onTap: () => setState(() {
        _filtreTip = tip;
        _filtrele();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _filtreTip == tip ? TsRenk.primary : context.borderColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              color: _filtreTip == tip ? Colors.white : context.textSecondary,
              fontWeight: _filtreTip == tip ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final musteri = _cari?.cariTipi == 'Müşteri' ||
        _cari?.cariTipi == 'Hem Müşteri Hem Tedarikçi';
    final fistipler = _tumHareketler.map((h) => h.fisTipi).toSet().toList()
      ..sort();

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(_secimIdleri.isNotEmpty
            ? '${_secimIdleri.length} fiş seçili'
            : (_cari?.unvan ?? 'Cari Hareketleri')),
        aksiyonlar: [
          if (_secimIdleri.isNotEmpty) ...[
            if (ref.read(authProvider).isMudur)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Seçili fişler için işlemler',
                onSelected: (v) {
                  if (v == 'fiyat') _secilenleriFiyatGuncelle();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'fiyat',
                    child: Text('Son fiyata göre güncelle'),
                  ),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Seçimi iptal et',
              onPressed: () => setState(() => _secimIdleri.clear()),
            ),
          ],
          IconButton(
              icon: const Icon(Icons.date_range),
              tooltip: 'Tarih Filtresi',
              onPressed: _tarihSec),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'excel') _exportExcel();
              if (v == 'csv') _exportCSV();
              if (v == 'pdf') _exportPDF();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'excel',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.download, color: AppRenkler.primary),
                      title: Text('Excel'))),
              PopupMenuItem(
                  value: 'csv',
                  child: ListTile(
                      dense: true,
                      leading:
                          Icon(Icons.table_chart, color: AppRenkler.primary),
                      title: Text('CSV'))),
              PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                      dense: true,
                      leading:
                          Icon(Icons.picture_as_pdf, color: AppRenkler.primary),
                      title: Text('PDF'))),
            ],
          ),
          IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Hareket Ekle',
              onPressed: _hareketEkle),
        ],
        gradyanli: false,
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [TsRenk.primary, TsRenk.primaryKoyu]),
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: _bakiyeItem('Borç', _toplamBorc, Colors.redAccent)),
            Expanded(
                child:
                    _bakiyeItem('Alacak', _toplamAlacak, Colors.greenAccent)),
            Expanded(child: _bakiyeItem(_turFiltreli ? 'Net' : 'Bakiye', _bakiye, _bakiyeRenk())),
          ]),
        ),
        if (fistipler.length > 1 || _tarihAralik != null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              _tipChip('Tümü', null),
              ...fistipler.map((t) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _tipChip(t, t))),
              if (_tarihAralik != null) ...[
                const SizedBox(width: 8),
                Chip(
                    label: Text(
                        '${_fmt.format(_tarihAralik!.start)} - ${_fmt.format(_tarihAralik!.end)}',
                        style: const TextStyle(fontSize: 11)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() {
                          _tarihAralik = null;
                          _devreden = 0;
                          _filtrele();
                        })),
              ],
            ]),
          ),
        Expanded(
            child: _yukleniyor
                ? const TsYukleniyor()
                : RefreshIndicator(
                    onRefresh: _yukle,
                    child: _filtreli.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                Icon(Icons.swap_vert,
                                    size: 56, color: context.textHint),
                                const SizedBox(height: 12),
                                Text('Hareket kaydı yok',
                                    style: TextStyle(
                                        color: context.textSecondary)),
                              ]))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _filtreli.length,
                            itemBuilder: (_, i) {
                              final h = _filtreli[i];

                              final bool pozitif;
                              final double tutar;
                              final Color renk;
                              final IconData ikonVeri;
                              // 🔥 ÖNCEDEN "borc > 0" / "alacak > 0" kontrolü, TEK bir
                              // alanın dolu olduğunu varsayıyordu. Ama Nakit/Kredi
                              // Kartı ile (cariye veresiye YAZILMADAN) yapılan satış/
                              // alımlar artık borc VE alacak'ı AYNI tutarda yazıyor
                              // (bakiyeyi etkilememek için, kasıtlı olarak net sıfır).
                              // Bu kontrol olmadan, bu kayıtlar YANLIŞLIKLA "veresiye
                              // artışı" gibi yeşil/kırmızı gösterilirdi — oysa
                              // gerçekte bakiyeye HİÇ dokunmuyorlar. Artık ayrı,
                              // nötr bir görsel durumla gösteriliyorlar.
                              if ((h.borc - h.alacak).abs() < 0.01 &&
                                  h.borc > 0) {
                                // Net sıfır — bakiyeyi etkilemeyen (Nakit/Kart) kayıt
                                pozitif = true;
                                tutar = h.borc;
                                renk = context.textSecondary;
                                ikonVeri = Icons.check_circle_outline;
                              } else if (musteri) {
                                // MÜŞTERİ
                                if (h.borc > 0) {
                                  // Veresiye satış - POZİTİF göster (+)
                                  pozitif = true;
                                  tutar = h.borc;
                                  renk = Colors.green.shade700;
                                  ikonVeri = Icons.arrow_downward;
                                } else {
                                  // Tahsilat - NEGATİF göster (-)
                                  pozitif = false;
                                  tutar = h.alacak;
                                  renk = Colors.red.shade700;
                                  ikonVeri = Icons.arrow_upward;
                                }
                              } else {
                                // TEDARİKÇİ
                                if (h.alacak > 0) {
                                  // Alım / Borçlandık → kırmızı - (borcumuz arttı)
                                  pozitif = false;
                                  tutar = h.alacak;
                                  renk = Colors.red.shade700;
                                  ikonVeri = Icons.arrow_upward;
                                } else {
                                  // Ödeme yaptık / Borcumuz azaldı → yeşil +
                                  pozitif = true;
                                  tutar = h.borc;
                                  renk = Colors.green.shade700;
                                  ikonVeri = Icons.arrow_downward;
                                }
                              }

                              return Dismissible(
                                key: ValueKey('ch_${h.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(12)),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white),
                                ),
                                confirmDismiss: (_) async =>
                                    await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        title: const Text('Hareketi Sil'),
                                        content: Text(_silHareketMesaji(h)),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('İptal')),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            style: FilledButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                backgroundColor: Colors.red),
                                            child: const Text('Sil'),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    false,
                                onDismissed: (_) => _silHareket(h),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: TsKart(
                                    padding: EdgeInsets.zero,
                                    onTap: _secimIdleri.isNotEmpty
                                        ? () => _secimDegistir(h)
                                        : () => _fisDetayinaGit(h),
                                    onLongPress: () => _secimDegistir(h),
                                    child: ListTile(
                                      selected: h.id != null &&
                                          _secimIdleri.contains(h.id),
                                      selectedTileColor:
                                          TsRenk.primary.withAlpha(30),
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: renk.withAlpha(26),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(ikonVeri,
                                            color: renk, size: 20),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              h.aciklama,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (h.fisId != null && h.fisId! > 0)
                                            IconButton(
                                              icon: Icon(Icons.receipt_long,
                                                  size: 18,
                                                  color: Colors.blue.shade600),
                                              onPressed: () =>
                                                  _fisDetayinaGit(h),
                                              tooltip: 'Fiş Detayı',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                        ],
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Text(_fmtT.format(h.tarih),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      context.textSecondary)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                                color: TsRenk.zemin(TsRenk.bilgi),
                                                borderRadius:
                                                    BorderRadius.circular(6)),
                                            child: Text(h.fisTipi,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        Colors.blue.shade700)),
                                          ),
                                        ],
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${pozitif ? "+" : "-"}${ParaUtils.formatla(tutar)}',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: renk),
                                          ),
                                          if (h.fisNo != null &&
                                              h.fisNo!.isNotEmpty)
                                            Text(h.fisNo!,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        context.textSecondary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  )),
      ]),
    );
  }
}
