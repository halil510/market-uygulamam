// lib/ekranlar/personel/personel_liste_ekrani.dart
//
// YENİ EKRAN — Personel Yönetimi
// DB'de personel tablosu vardı ama ekran yoktu.
// Özellikler: liste, detay, ekle/düzenle, mesai takibi, maaş raporu

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../modeller/personel_model.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

// ── Personel Provider ─────────────────────────────────────────────────────────

final personellerProvider =
    FutureProvider.autoDispose<List<PersonelModel>>((ref) async {
  final db   = await Veritabani().db;
  final rows = await db.query(
    DbSabitler.personel,
    where: 'is_deleted = 0',
    orderBy:  'ad_soyad ASC',
  );
  return rows.map(PersonelModel.fromMap).toList();
});

// ── Ekran ─────────────────────────────────────────────────────────────────────

class PersonelListeEkrani extends ConsumerStatefulWidget {
  const PersonelListeEkrani({super.key});

  @override
  ConsumerState<PersonelListeEkrani> createState() =>
      _PersonelListeEkraniState();
}

class _PersonelListeEkraniState extends ConsumerState<PersonelListeEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _araCtrl = TextEditingController();
  String _aramaMetni = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _araCtrl.addListener(() {
      if (_aramaMetni != _araCtrl.text) {
        setState(() => _aramaMetni = _araCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _araCtrl.dispose();
    super.dispose();
  }

  List<PersonelModel> _filtrele(List<PersonelModel> liste) {
    if (_aramaMetni.isEmpty) return liste;
    final q = _aramaMetni.toLowerCase();
    return liste.where((p) =>
        p.adSoyad.toLowerCase().contains(q) ||
        (p.pozisyon?.toLowerCase().contains(q) ?? false) ||
        (p.telefon?.contains(q) ?? false)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final personellerAsync = ref.watch(personellerProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Personel Yönetimi',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(personellerProvider),
          ),
        ],
        alt: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Personel Listesi'),
            Tab(text: 'Maaş Özeti'),
          ],
        ),
      ),
      body: personellerAsync.when(
        loading: () => const Center(child: const AppYukleniyor()),
        error:   (e, _) => BosEkran(ikon: Icons.inbox_outlined, baslik: 'Hata: $e'),
        data:    (liste) => TabBarView(
          controller: _tab,
          children: [
            _PersonelListeTab(
              personeller:  _filtrele(liste),
              araCtrl:      _araCtrl,
              onDegisti:    () => ref.invalidate(personellerProvider),
            ),
            _MaasOzetiTab(personeller: liste),
          ],
        ),
      ),
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        onPressed: () => _personelEkleDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Personel Ekle'),
      )),
    );
  }

  Future<void> _personelEkleDialog(BuildContext ctx) async {
    try {  
      final result = await showModalBottomSheet<bool>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PersonelFormSheet(),
      );
      if (result == true) ref.invalidate(personellerProvider);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }
}

// ── Personel Liste Tab ────────────────────────────────────────────────────────

class _PersonelListeTab extends StatelessWidget {
  final List<PersonelModel> personeller;
  final TextEditingController araCtrl;
  final VoidCallback onDegisti;

  const _PersonelListeTab({
    required this.personeller,
    required this.araCtrl,
    required this.onDegisti,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Arama
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: araCtrl,
            decoration: InputDecoration(
              hintText: 'İsim veya departman ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: araCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => araCtrl.clear())
                  : null,
              filled: true,
              fillColor: TsRenk.kart(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // İstatistik chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            _StatChip('${personeller.length} Personel',
                Icons.people, AppRenkler.primary),
            const SizedBox(width: 8),
            _StatChip(
                '${personeller.where((p) => p.aktif).length} Aktif',
                Icons.check_circle, Colors.green),
          ]),
        ),

        // Liste
        Expanded(
          child: personeller.isEmpty
              ? const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Personel bulunamadı')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: personeller.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) =>
                      _PersonelKarti(personel: personeller[i], onDegisti: onDegisti),
                ),
        ),
      ],
    );
  }
}

// ── Personel Kartı ────────────────────────────────────────────────────────────

class _PersonelKarti extends StatelessWidget {
  final PersonelModel personel;
  final VoidCallback onDegisti;
  const _PersonelKarti({required this.personel, required this.onDegisti});

  @override
  Widget build(BuildContext context) {
    final renkler = [
      Colors.blue.shade600, Colors.purple.shade600, Colors.teal.shade600,
      Colors.orange.shade600, Colors.pink.shade600,
    ];
    final renk = renkler[personel.adSoyad.codeUnitAt(0) % renkler.length];

    return TsKart.liste(
      ikon: Text(
        personel.adSoyad.isNotEmpty ? personel.adSoyad[0].toUpperCase() : '?',
        style: TextStyle(color: renk, fontWeight: FontWeight.w700, fontSize: 18),
      ),
      baslik: personel.adSoyad,
      altBaslik: [
        if (personel.pozisyon != null) personel.pozisyon!,
        if (personel.telefon != null) personel.telefon!,
      ].join(' · '),
      sagAksiyon: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TsBadge(
            metin: personel.aktif ? 'AKTİF' : 'PASİF',
            tur: personel.aktif ? TsBadgeTuru.basarili : TsBadgeTuru.hata,
          ),
          if (personel.maas != null && personel.maas! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ParaUtils.formatla(personel.maas!),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
            ),
        ],
      ),
      onTap: () => _detayGoster(context),
    );
  }

  void _detayGoster(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PersonelDetaySheet(personel: personel, onDegisti: onDegisti),
    );
  }
}

// ── Maaş Özeti Tab ────────────────────────────────────────────────────────────

class _MaasOzetiTab extends StatelessWidget {
  final List<PersonelModel> personeller;
  const _MaasOzetiTab({required this.personeller});

  @override
  Widget build(BuildContext context) {
    final aktifler = personeller.where((p) => p.aktif).toList();
    final toplamMaas = aktifler.fold(
        0.0, (s, p) => s + (p.maas ?? 0));
    final departmanlar = <String, List<PersonelModel>>{};
    for (final p in aktifler) {
      departmanlar.putIfAbsent(p.pozisyon ?? 'Genel', () => []).add(p);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Toplam maaş kartı
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [TsRenk.primary, TsRenk.primaryKoyu],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aylık Toplam Maaş',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Text(ParaUtils.formatla(toplamMaas),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.w800)),
                Text('${aktifler.length} aktif personel',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            )),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.payments_outlined,
                  color: Colors.white, size: 36),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // Departman bazlı özet
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Departman Bazlı',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),

        ...departmanlar.entries.map((e) {
          final dept = e.key;
          final personeller = e.value;
          final maasToplam = personeller.fold(0.0, (s, p) => s + (p.maas ?? 0));
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppRenkler.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.business, color: AppRenkler.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dept, style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('${personeller.length} personel',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                ],
              )),
              Text(ParaUtils.formatla(maasToplam),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15,
                      color: AppRenkler.primary)),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Personel Detay Sheet ──────────────────────────────────────────────────────

class _PersonelDetaySheet extends StatelessWidget {
  final PersonelModel personel;
  final VoidCallback onDegisti;
  const _PersonelDetaySheet({required this.personel, required this.onDegisti});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: TsRenk.ayirac(context),
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),

        Row(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Color.fromARGB(26, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
            child: Text(
              personel.adSoyad.isNotEmpty ? personel.adSoyad[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppRenkler.primary, fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(personel.adSoyad,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (personel.pozisyon != null)
              Text(personel.pozisyon ?? 'Pozisyon yok',
                  style: TextStyle(color: TsRenk.metinIkincil(context))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: personel.aktif ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(personel.aktif ? 'Aktif' : 'Pasif',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: personel.aktif ? Colors.green.shade700 : Colors.red.shade700,
                )),
          ),
        ]),

        const Divider(height: 28),

        
        
        if (personel.maas != null)
          _BilgiSatiri('Maaş', ParaUtils.formatla(personel.maas!), Icons.payments),
        if (personel.iseBaslama != null)
          _BilgiSatiri('İşe Başlama',
              DateFormat('dd.MM.yyyy').format(personel.iseBaslama!),
              Icons.calendar_today),

        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Düzenle'),
              onPressed: () async {
                // ÖNCEDEN BU BUTON HİÇBİR ŞEY YAPMIYORDU — sadece detay
                // sayfasını kapatıyordu, düzenleme formu hiç açılmıyordu.
                Navigator.pop(context);
                final result = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _PersonelFormSheet(personel: personel),
                );
                if (result == true) onDegisti();
              },
            ),
          ),
        ]),
      ]),
    );
  }
}

class _BilgiSatiri extends StatelessWidget {
  final String baslik;
  final String deger;
  final IconData ikon;
  const _BilgiSatiri(this.baslik, this.deger, this.ikon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(ikon, size: 18, color: TsRenk.metinIkincil(context)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(baslik, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
          Text(deger, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }
}

// ── Personel Ekle/Düzenle Form ────────────────────────────────────────────────

class _PersonelFormSheet extends ConsumerStatefulWidget {
  final PersonelModel? personel;
  const _PersonelFormSheet({this.personel});

  @override
  ConsumerState<_PersonelFormSheet> createState() => _PersonelFormSheetState();
}

class _PersonelFormSheetState extends ConsumerState<_PersonelFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _adCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _deptCtrl;
  late final TextEditingController _maasCtrl;
  bool _aktif = true;
  bool _yukleniyor = false;

  @override
  void initState() {
    super.initState();
    final p = widget.personel;
    _adCtrl    = TextEditingController(text: p?.adSoyad);
    _telCtrl   = TextEditingController(text: p?.telefon);
    _emailCtrl = TextEditingController(text: p?.email);
    _deptCtrl  = TextEditingController(text: p?.departman);
    _maasCtrl  = TextEditingController(text: p?.maas.toString());
    _aktif     = p?.aktif ?? true;
  }

  @override
  void dispose() {
    _adCtrl.dispose(); _telCtrl.dispose(); _emailCtrl.dispose();
    _deptCtrl.dispose(); _maasCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _yukleniyor = true);
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      final veri = {
        'ad_soyad': _adCtrl.text.trim(),
        // NOT: _deptCtrl formda "Departman" etiketiyle gösteriliyor ama
        // PersonelModel.departman, 'pozisyon' sütununun bilinçli bir
        // geriye-dönük-uyumluluk alias'ıdır (bkz. personel_model.dart
        // "Geriye dönük uyumluluk için alias getter" notu) — gerçek
        // veri hep 'pozisyon' sütununda tutulur, 'departman' sütunu
        // (şemada var ama modelde hiç okunmuyor) kasıtlı olarak
        // kullanılmaz. Bu satır DOĞRU şekilde 'pozisyon'a yazıyor.
        'pozisyon': _deptCtrl.text.trim().isEmpty ? null : _deptCtrl.text.trim(),
        // ÖNCEDEN: telefon ve email alanları formda toplanıyordu ama
        // kaydetme sırasında tamamen görmezden geliniyordu — kullanıcı
        // doldursa bile veri sessizce kayboluyordu.
        'telefon':  _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'email':    _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'maas':     double.tryParse(_maasCtrl.text.replaceAll(',', '.')) ?? 0,
        'aktif':    _aktif ? 1 : 0,
        // 🔴 DÜZELTME (gerçek bulgu): 'notlar' HARDCODED null
        // yazılıyordu — DÜZENLEME modunda mevcut bir not varsa bile
        // sessizce siliniyordu (form bu alanı hiç göstermediği için
        // kullanıcı bunu fark edemezdi). Artık düzenlemede dokunulmuyor.
        if (widget.personel == null) 'notlar': null,
        'last_updated': now,
      };
      int personelId;
      if (widget.personel == null) {
        // 🔴 Derin analizde bulundu: global_id hiç atanmıyordu,
        // BulutManager hiç çağrılmıyordu — personel senkron sisteminde
        // olduğu halde yeni personel eklemek/düzenlemek diğer
        // cihazlara hiç yansımıyordu.
        veri['global_id'] = const Uuid().v4();
        personelId = await db.insert(DbSabitler.personel, veri);
      } else {
        personelId = widget.personel!.id!;
        await db.update(DbSabitler.personel, veri,
            where: 'id = ?', whereArgs: [personelId]);
      }
      final satir = await db.query(DbSabitler.personel, where: 'id = ?', whereArgs: [personelId], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert(DbSabitler.personel, Map<String, dynamic>.from(satir.first));
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: TsRenk.ayirac(context),
                  borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text(widget.personel == null ? 'Yeni Personel' : 'Personel Düzenle',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _adCtrl,
              decoration: const InputDecoration(labelText: 'Ad Soyad *', prefixIcon: Icon(Icons.person)),
              validator: (v) => (v == null || v.isEmpty) ? 'Ad soyad zorunlu' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefon', prefixIcon: Icon(Icons.phone)),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _maasCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Maaş (₺)', prefixIcon: Icon(Icons.payments)),
              )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _deptCtrl,
              decoration: const InputDecoration(labelText: 'Departman', prefixIcon: Icon(Icons.business)),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _aktif,
              onChanged: (v) => setState(() => _aktif = v),
              title: const Text('Aktif Personel'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _yukleniyor ? null : _kaydet,
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _yukleniyor
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(widget.personel == null ? 'Kaydet' : 'Güncelle',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Stat Chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String metin;
  final IconData ikon;
  final Color renk;
  const _StatChip(this.metin, this.ikon, this.renk);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: renk.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon, size: 14, color: renk),
        const SizedBox(width: 6),
        Text(metin, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: renk)),
      ]),
    );
  }
}
