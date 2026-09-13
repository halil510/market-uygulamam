// lib/ekranlar/tedarik/tedarik_siparis_ekrani.dart ✅ TAM YAZILDI
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/cari_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/ts_kart.dart';
import '../../tasarim_sistemi/ts_yetki.dart';

class TedarikSiparisEkrani extends ConsumerStatefulWidget {
  const TedarikSiparisEkrani({super.key});
  @override
  ConsumerState<TedarikSiparisEkrani> createState() => _TedarikSiparisEkraniState();
}

class _TedarikSiparisEkraniState extends ConsumerState<TedarikSiparisEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _cariDepo = CariDeposu();
  List<Map<String, dynamic>> _siparisler = [];
  bool _yukleniyor = true;
  String? _durumFiltre;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() { if (_tab.indexIsChanging) WidgetsBinding.instance.addPostFrameCallback((_) => _yukle()); });
    _yukle();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String get _aktifDurum {
    switch (_tab.index) {
      case 0: return 'beklemede';
      case 1: return 'teslim_alindi';
      case 2: return 'iptal';
      default: return 'beklemede';
    }
  }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final db = await Veritabani().db;
      final durum = _aktifDurum;
      final rows = await db.rawQuery(
        'SELECT ts.*, c.unvan as tedarikci_adi '
        'FROM tedarikci_siparisler ts '
        'LEFT JOIN cari c ON ts.cari_id = c.id '
        'WHERE ts.durum = ? '
        'ORDER BY ts.siparis_tarihi DESC',
        [durum],
      );
      if (mounted) setState(() { _siparisler = rows; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _yeniSiparis() async {
    try {
      // Tedarikçi seç
      final tedarikci = await _tedarikciSec();
      if (tedarikci == null) return;
      if (!mounted) return;
      final kaydedildi = await context.push<bool>('/tedarik/siparis-olustur', extra: tedarikci);
      if (kaydedildi == true) await _yukle();
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  // 🔴 Derin analizde bulundu: bu ekranın 'Bekleyen'/'İptal' sekmeleri
  // hiçbir zaman dolmuyordu çünkü 'Sipariş Ver' doğrudan Alım (mal kabul)
  // ekranına atlıyor, hiç 'beklemede' kayıt açmıyordu; ayrıca Alım ekranı
  // durum='tamamlandi' yazıyordu ki bu üç sekmeden HİÇBİRİYLE eşleşmiyordu
  // (tab'lar 'beklemede'/'teslim_alindi'/'iptal' bekliyor). Artık
  // SiparisOlusturEkrani gerçek bir 'beklemede' sipariş açıyor, Alım
  // ekranı ise durum='teslim_alindi' yazıyor — üçü de anlamlı hale geldi.
  Future<void> _teslimAl(Map<String, dynamic> siparis) async {
    try {
      final db = await Veritabani().db;
      final kalemler = await db.rawQuery(
        'SELECT * FROM tedarikci_siparis_kalem WHERE siparis_id = ?',
        [siparis['id']],
      );
      if (kalemler.isEmpty) {
        if (mounted) BildirimServisi.uyari(context, 'Siparişte kalem yok');
        return;
      }
      final tedarikci = await _cariDepo.idileGetir(siparis['cari_id'] as int);
      if (tedarikci == null || !mounted) return;
      final aktarilanKalemler = kalemler.map((k) {
        final siparisMik = (k['siparis_mik'] as num?)?.toDouble() ?? 0;
        final teslimMik  = (k['teslim_mik'] as num?)?.toDouble() ?? 0;
        final kalanMik   = (siparisMik - teslimMik).clamp(0, double.infinity);
        return {
          'urunId':    k['urun_id'],
          'miktar':    kalanMik > 0 ? kalanMik : siparisMik,
          'alisFiyat': k['birim_fiyat'],
        };
      }).toList();
      await context.push('/tedarik/alim', extra: {
        'tedarikci': tedarikci,
        'kalemler':  aktarilanKalemler,
        'siparisId': siparis['id'],
      });
      if (mounted) await _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<CariModel?> _tedarikciSec() async {
    final cariler = await _cariDepo.tumunuGetir(tip: 'Tedarikçi');
    if (!mounted) return null;
    return showModalBottomSheet<CariModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TedarikciSecimPaneli(cariler: cariler),
    );
  }

  Future<void> _durumDegistir(Map<String, dynamic> siparis, String yeniDurum) async {
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      await db.update('tedarikci_siparisler',
          {'durum': yeniDurum, 'last_updated': now},
          where: 'id = ?', whereArgs: [siparis['id']]);
      // 🔴 Derin analizde bulundu: last_updated hiç ayarlanmıyordu,
      // BulutManager hiç çağrılmıyordu.
      final satir = await db.query('tedarikci_siparisler', where: 'id = ?', whereArgs: [siparis['id']], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('tedarikci_siparisler', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Durum güncellendi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _siparisDetay(Map<String, dynamic> siparis) async {
    final db = await Veritabani().db;
    final kalemler = await db.rawQuery(
      'SELECT tsk.*, u.urun_adi, u.birim_adi '
      'FROM tedarikci_siparis_kalem tsk '
      'LEFT JOIN urunler u ON tsk.urun_id = u.id '
      'WHERE tsk.siparis_id = ?',
      [siparis['id']],
    );
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SiparisDetayPanel(siparis: siparis, kalemler: kalemler),
    );
  }

  Color _durumRenk(String durum) {
    switch (durum) {
      case 'beklemede': return Colors.orange;
      case 'teslim_alindi': return AppRenkler.success;
      case 'iptal': return AppRenkler.error;
      default: return context.textSecondary;
    }
  }

  String _durumEtiket(String durum) {
    switch (durum) {
      case 'beklemede': return 'Beklemede';
      case 'teslim_alindi': return 'Teslim Alındı';
      case 'iptal': return 'İptal';
      default: return durum;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Tedarikçi Siparişleri',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle),
        ],
        alt: TabBar(controller: _tab, tabs: const [
          Tab(text: 'Bekleyen'),
          Tab(text: 'Teslim Alınan'),
          Tab(text: 'İptal'),
        ]),
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: TsRenk.primary))
          : _siparisler.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 64, color: context.textHint),
                    const SizedBox(height: 12),
                    Text('${_durumEtiket(_aktifDurum)} sipariş yok',
                        style: TextStyle(color: context.textSecondary)),
                    if (_tab.index == 0) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Sipariş Ver'),
                        onPressed: _yeniSiparis,
                      ),
                    ],
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _yukle,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _siparisler.length,
                    itemBuilder: (_, i) {
                      final s = _siparisler[i];
                      final durum = s['durum'] as String? ?? '';
                      final tarih = DateTime.tryParse(
                          s['siparis_tarihi']?.toString() ?? '');
                      final toplam =
                          (s['toplam_tutar'] as num?)?.toDouble() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: TsKart(
                          onTap: () => _siparisDetay(s),
                          padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                  child: Text(
                                    s['tedarikci_adi'] as String? ?? 'Tedarikçi',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Color.fromARGB(26, _durumRenk(durum).red, _durumRenk(durum).green, _durumRenk(durum).blue),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color:
                                            Color.fromARGB(76, _durumRenk(durum).red, _durumRenk(durum).green, _durumRenk(durum).blue)),
                                  ),
                                  child: Text(_durumEtiket(durum),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _durumRenk(durum),
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                Icon(Icons.receipt_outlined,
                                    size: 14, color: context.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  'No: ${s['siparis_no'] ?? '-'}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.textSecondary),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.calendar_today_outlined,
                                    size: 14, color: context.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  tarih != null
                                      ? DateFormat('dd.MM.yyyy').format(tarih)
                                      : '-',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.textSecondary),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                Text(ParaUtils.formatla(toplam),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: AppRenkler.primary)),
                                if (durum == 'beklemede')
                                  Row(children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Teslim Al'),
                                      onPressed: () => _teslimAl(s),
                                      style: TextButton.styleFrom(
                                          foregroundColor: AppRenkler.success),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.close, size: 16),
                                      label: const Text('İptal'),
                                      onPressed: () =>
                                          _durumDegistir(s, 'iptal'),
                                      style: TextButton.styleFrom(
                                          foregroundColor: AppRenkler.error),
                                    ),
                                  ]),
                              ]),
                            ]),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: _tab.index == 0
          ? TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
              onPressed: _yeniSiparis,
              icon: const Icon(Icons.add),
              label: const Text('Sipariş Ver'),
            ))
          : null,
    );
  }
}

class _TedarikciSecimPaneli extends ConsumerStatefulWidget {
  final List<CariModel> cariler;
  const _TedarikciSecimPaneli({required this.cariler});
  @override
  ConsumerState<_TedarikciSecimPaneli> createState() => _TedarikciSecimPaneliState();
}

class _TedarikciSecimPaneliState extends ConsumerState<_TedarikciSecimPaneli> {
  final _araCtrl = TextEditingController();
  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final q = _araCtrl.text.toLowerCase();
    final liste = q.isEmpty
        ? widget.cariler
        : widget.cariler.where((c) => c.unvan.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: context.borderColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _araCtrl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Tedarikçi ara...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: liste.isEmpty
              ? const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Tedarikçi bulunamadı')
              : ListView.builder(
                  controller: ctrl,
                  itemCount: liste.length,
                  itemBuilder: (_, i) {
                    final c = liste[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color.fromARGB(26, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
                        child: Text(c.unvan[0],
                            style: const TextStyle(color: AppRenkler.primary)),
                      ),
                      title: Text(c.unvan),
                      subtitle: c.telefon != null ? Text(c.telefon!) : null,
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _SiparisDetayPanel extends StatelessWidget {
  final Map<String, dynamic> siparis;
  final List<Map<String, dynamic>> kalemler;
  const _SiparisDetayPanel({required this.siparis, required this.kalemler});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: context.borderColor, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Sipariş Detayı',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tedarikçi: ${siparis['tedarikci_adi'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Sipariş No: ${siparis['siparis_no'] ?? '-'}'),
            Text('Toplam: ${ParaUtils.formatla((siparis['toplam_tutar'] as num?)?.toDouble() ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppRenkler.primary)),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            controller: ctrl,
            itemCount: kalemler.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (_, i) {
              final k = kalemler[i];
              final miktar = (k['siparis_mik'] as num?)?.toDouble() ?? 0;
              final teslim = (k['teslim_mik'] as num?)?.toDouble() ?? 0;
              final fiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
              return ListTile(
                dense: true,
                title: Text(k['urun_adi'] as String? ?? '-'),
                subtitle: Text('${miktar.toStringAsFixed(0)} ${k['birim_adi'] ?? 'Adet'} × ${ParaUtils.formatla(fiyat)}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(ParaUtils.formatla(miktar * fiyat),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Teslim: ${teslim.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11,
                          color: teslim >= miktar ? AppRenkler.success : Colors.orange)),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
