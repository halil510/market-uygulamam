// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: Bu dosya `part of 'iade_ekrani.dart'` ve içeriği
// `extension ... on _IadeEkraniState` olarak yazılmış. Bu desen 3000
// satırlık iade ekranını okunabilir parçalara bölmek için bilinçli
// seçilmiş ve ÇALIŞIYOR — `setState` gerçekten kendi State sınıfının
// üzerinde çağrılıyor.
//
// Ama Dart analizcisi `setState`'i @protected gördüğü için, extension
// içinden çağrıyı "korumalı üyeye dışarıdan erişim" sayıyor. Derlemeyi
// engellemez; sadece analiz uyarısıdır.
//
// (analysis_options.yaml'da bu kural bilinçli olarak `error` seviyesine
// çıkarıldı — başka yerlerde gerçek hataları yakalasın diye. Burada
// dosya bazında muaf tutuluyor.)
// lib/ekranlar/satis/iade_ekrani_gecmis.dart
//
// "Geçmiş" (İade Geçmişi) sekmesinin TÜM mantığı buraya taşındı —
// iade_ekrani.dart'ın 2273 satırlık, tek dosyada aşırı büyümüş
// yapısını daha yönetilebilir hale getirmek için. Bu, Dart'ın
// part/part of mekanizmasıyla yapıldı: bu dosya, iade_ekrani.dart ile
// AYNI "kütüphane" kapsamındadır — hiçbir mantık/davranış DEĞİŞMEDİ,
// sadece kod organizasyonu değişti. TabBar/TabBarView yapısı,
// kullanıcı deneyimi (navigasyon) AYNEN korundu — kullanıcı hiçbir
// fark görmeyecek, sadece kod artık daha kolay bakım yapılabilir.
part of 'iade_ekrani.dart';

extension _GecmisTabExt on _IadeEkraniState {
  Widget _gecmisTab() => IadeGecmisSekmesi(
        baslangic: _gecmisTarihBaslangic,
        bitis: _gecmisTarihBitis,
        cariFiltre: _gecmisCariFiltre,
        yukleniyor: _gecmisYukleniyor,
        iadeler: _gecmisIadeler,
        onBaslangicSec: () => _gecmisTarihSec(baslangic: true),
        onBitisSec: () => _gecmisTarihSec(baslangic: false),
        onCariSec: _gecmisCariSec,
        onFiltreTemizle: _gecmisFiltreTemizle,
        onYenile: _gecmisYukle,
        onSilOnay: _gecmisSilOnay,
        onSil: _gecmisIadeSil,
        onDetay: _gecmisIadeDetay,
      );

  // ── Geçmiş filtreleri ────────────────────────────────────────────────────
  Future<void> _gecmisTarihSec({required bool baslangic}) async {
    final d = await showDatePicker(
        context: context,
        initialDate: (baslangic ? _gecmisTarihBaslangic : _gecmisTarihBitis) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (!mounted || d == null) return;
    setState(() => baslangic ? _gecmisTarihBaslangic = d : _gecmisTarihBitis = d);
    _gecmisYukle();
  }

  Future<void> _gecmisCariSec() async {
    final secilen = await showDialog<CariModel>(
        context: context, builder: (bCtx) => CariSecDialog(cariler: _cariler));
    if (!mounted || secilen == null) return;
    setState(() => _gecmisCariFiltre = secilen);
    _gecmisYukle();
  }

  void _gecmisFiltreTemizle() {
    setState(() {
      _gecmisTarihBaslangic = null;
      _gecmisTarihBitis = null;
      _gecmisCariFiltre = null;
    });
    _gecmisYukle();
  }

  Future<bool> _gecmisSilOnay(Map<String, dynamic> r) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Fisi Sil'),
        content: Text('${r['fis_no'] ?? 'Bu iade'} silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayir')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    return onay == true;
  }

  Future<void> _gecmisIadeyiDevamEt(Map<String, dynamic> iade) async {
    final iadeId = iade['id'] as int?;
    if (iadeId == null) return;

    // DB'den kalemleri çek — Madde 2 sertleştirmesi (2026-09-22):
    // doğrudan Veritabani().db erişimi kaldırıldı.
    final kalemler = await IadeDeposu().kalemleriGetir(iadeId);

    // Cari bul
    CariModel? cari;
    final cariId = iade['cari_id'];
    if (cariId != null) {
      cari = _cariler.firstWhere(
        (c) => c.id == cariId,
        orElse: () => CariModel(id: cariId, unvan: iade['cari_adi']?.toString() ?? '-', bakiye: 0),
      );
    }

    if (!mounted) return;

    // Onay al
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.edit_note, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(child: Text('İadeyi Düzenle', style: TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: TsRenk.zemin(TsRenk.uyari),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fiş: ${iade['fis_no'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (cari != null)
                Text('Cari: ${cari.unvan}',
                    style: TextStyle(fontSize: 12, color: context.textSecondary)),
              Text('Tutar: ${ParaUtils.formatla((iade['toplam_tutar'] as num?)?.toDouble() ?? 0)}',
                  style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            'Bu iade fise eklenecek. Yeni urun secip kaydedebilirsiniz.',
            style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context), height: 1.5),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton.icon(
            icon: const Icon(Icons.edit, size: 16, color: Colors.white),
            label: const Text('Düzenlemeye Geç'),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (onay != true || !mounted) return;

    // İade sekmesine geç ve düzenleme modunu aç
    setState(() {
      _duzenlemeModu_iadeId  = iadeId;
      _duzenlemeModu_fisNo   = iade['fis_no']?.toString();
      _secilenCari           = cari;
      _oturumIadeId          = iadeId;        // Devam modunda oturum ID set et
      _oturumFisNo           = iade['fis_no']?.toString() ?? '';

      // Mevcut kalemleri listeye yükle
      _iadeListesi.clear();
      for (final k in kalemler) {
        final miktar    = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birimFiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        _iadeListesi.add({
          'iade_id':      iadeId,
          'kalem_id':     k['id'],
          'urun_id':      k['urun_id'],
          'tarih':        DateTime.now(),
          'urun_adi':     k['urun_adi'],
          'barkod':       '',
          'miktar':       miktar,
          'birim_fiyat':  birimFiyat,
          'iskonto_oran': (k['iskonto_oran'] as num?)?.toDouble() ?? 0.0,
          'iskonto_tutar': (k['iskonto_tutar'] as num?)?.toDouble() ?? 0.0,
          'toplam_tutar': (k['toplam'] as num?)?.toDouble() ?? miktar * birimFiyat,
          'musteri_adi':  cari?.unvan ?? 'Perakende',
          'cari_id':      cariId,
          'aciklama':     iade['iade_nedeni']?.toString() ?? '',
          'fis_no':       iade['fis_no']?.toString() ?? '',
          'mevcut_kalem': true,  // DB kayitli kalem
        });
      }
    });

    // İade sekmesine git
    _gecmisYukle(); // Geçmişi güncelle
    _tab.animateTo(0);
    _msg('Düzenleme modu: ${iade['fis_no']} — Yeni ürün ekleyebilirsiniz', err: false);
  }

  Future<void> _gecmisIadeSil(Map<String, dynamic> iade) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Fişi Sil'),
        ]),
        content: Text('${iade['fis_no'] ?? 'Bu iade'} silinecek.\nStok, kasa ve cari kayıtları geri alınacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    try {
      final iadeId  = iade['id'] as int?;
      if (iadeId == null) return;

      // Madde 2 sertleştirmesi (2026-09-22): doğrudan Veritabani().db
      // erişimi kaldırıldı.
      final kalemler = await IadeDeposu().kalemleriGetir(iadeId);

      // Tüm transaction + bulut senkron mantığı artık
      // IadeIslemServisi.gecmisFisIadeSil'de — bkz. o metodun doc
      // yorumu, davranış birebir korundu.
      await IadeIslemServisi().gecmisFisIadeSil(
        iadeId: iadeId,
        kalemler: kalemler,
        toplamTutar: (iade['toplam_tutar'] as num?)?.toDouble() ?? 0,
        cariId: iade['cari_id'] as int?,
        fisNo: iade['fis_no']?.toString(),
      );

      _gecmisYukle();
      if (mounted) _msg('Fis silindi: ${iade['fis_no']}', err: false);
    } catch (e) {
      if (mounted) _msg('Hata: $e', err: true);
    }
  }

  Future<void> _gecmisYukle() async {
    if (!mounted) return;
    _gecmisYukleniyor = true;
    if (mounted) setState(() {});
    try {
      // Madde 2 sertleştirmesi (2026-09-22): doğrudan Veritabani().db
      // erişimi kaldırıldı — IadeDeposu.gecmisListesiGetir() üzerinden,
      // davranış birebir korunarak.
      final rows = await IadeDeposu().gecmisListesiGetir(
        baslangic: _gecmisTarihBaslangic,
        bitis: _gecmisTarihBitis,
        cariId: _gecmisCariFiltre?.id,
      );
      if (!mounted) return;
      _gecmisIadeler = rows;
      _gecmisYukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) { _gecmisYukleniyor = false; setState(() {}); }
    }
  }

  Future<void> _iadeyiFaturalandir(
      Map<String, dynamic> iade, List<Map<String, dynamic>> kalemler) async {
    final cariId = iade['cari_id'] as int?;
    if (cariId == null) {
      _msg('Bu iadede cari secilmemis. Faturalandirma icin once carisini secmelisiniz.', err: true);
      return;
    }
    if (kalemler.isEmpty) {
      _msg('Faturalandirilacak kalem bulunamadi.', err: true);
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      // Bu iade için daha önce fatura kesildiyse tekrar oluşturma
      final mevcutId = await FaturalandirmaServisi.mevcutFaturaId(iadeId: iade['id'] as int?);
      if (mevcutId != null) {
        if (!mounted) return;
        _msg('Bu iade için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.', err: false);
        context.push('/fatura/detay/$mevcutId');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(cariId);
      if (kontrol == null) {
        if (mounted) _msg('Cari bulunamadi.', err: true);
        return;
      }

      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${kontrol.cari.unvan.isEmpty ? 'Bu cari' : kontrol.cari.unvan} icin "
                  "fatura kesilebilmesi icin asagidaki bilgiler eksik:"),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgec')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Duzenle')),
            ],
          ),
        );
        if (git == true && mounted) {
          await context.push('/cari/ekle', extra: kontrol.cari);
        }
        return;
      }

      final detaylar = kalemler.map((k) {
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birimFiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        // Ürünün gerçek KDV oranı (urunler.kdv_oran); bulunamazsa %20.
        final kdvOran = (k['urun_kdv_oran'] as num?)?.toDouble() ?? 20.0;
        // İade fişindeki GERÇEK kalem tutarı (iskonto dahil) esas alınır;
        // yoksa miktar × birim fiyat. Önceden iskontolu iade faturaya
        // iskontosuz (fazla) tutarla yazılıyordu.
        final kdvDahilToplam =
            (k['toplam'] as num?)?.toDouble() ?? miktar * birimFiyat;
        return FaturaDetayModel.kdvDahilKalemden(
          urunId: k['urun_id'] as int?,
          urunAdi: (k['urun_adi'] ?? k['urun_adi_db'] ?? '-').toString(),
          miktar: miktar,
          birimFiyat: birimFiyat,
          kdvOrani: kdvOran,
          kdvDahilToplam: kdvDahilToplam,
        );
      }).toList();

      final tarih = DateTime.tryParse(iade['tarih']?.toString() ?? '') ?? DateTime.now();
      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Iade',
        iadeId: iade['id'] as int?,
        tarih: tarih,
      );

      if (!mounted) return;
      _msg('Iade faturasi olusturuldu', err: false);
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) _msg('Faturalandirma hatasi: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _gecmisIadeDetay(Map<String, dynamic> iade) async {
    // Madde 2 sertleştirmesi (2026-09-22): doğrudan Veritabani().db
    // erişimi kaldırıldı.
    final kalemler =
        await IadeDeposu().kalemleriUrunBilgisiyleGetir(iade['id'] as int);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('İade #${iade['fis_no'] ?? iade['id']}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.orange),
            tooltip: 'Düzelt',
            onPressed: () {
              Navigator.pop(ctx);
              _gecmisIadeyiDevamEt(iade);
            },
          ),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (iade['cari_adi'] != null)
              ListTile(dense: true, leading: const Icon(Icons.person, size: 18, color: AppRenkler.primary),
                  title: Text(iade['cari_adi'].toString())),
            const Divider(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: kalemler.length,
                itemBuilder: (_, i) {
                  final k = kalemler[i];
                  final m = (k['miktar'] as num?)?.toDouble() ?? 0;
                  final bf = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
                  return ListTile(dense: true,
                    title: Text(k['urun_adi']?.toString() ?? k['urun_adi_db']?.toString() ?? '-',
                        style: const TextStyle(fontSize: 13)),
                    trailing: Text('${m.toStringAsFixed(m%1==0?0:2)} × ${ParaUtils.formatla(bf)}',
                        style: const TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TOPLAM', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(ParaUtils.formatla((iade['toplam_tutar'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
            ]),
          ]),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _gecmisIadeSil(iade);
            },
            child: const Text('Fişi Sil'),
          ),
          if (iade['cari_id'] != null)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Faturalandır'),
              onPressed: () {
                Navigator.pop(ctx);
                _iadeyiFaturalandir(iade, kalemler);
              },
            ),
          // 🔴 DÜZELTME (komple derin analizde bulundu): _gecmisIadeDuzelt()
          // tam/çalışan bir fonksiyondu (iade nedenini düzenleyip
          // BulutManager().upsert() ile senkronluyordu) ama hiçbir UI
          // tetikleyicisi yoktu — analyzer'ın "unused_element" uyarısı
          // vermemesi çağrılıyor sanılmasına yol açmıştı, oysa hiçbir yerde
          // çağrılmıyordu. "Düzenle" (kalem ekleme) ile karıştırılmaması
          // için ayrı, küçük bir ikon buton olarak bağlandı.
          TextButton.icon(
            icon: const Icon(Icons.edit_note_outlined, size: 18),
            label: const Text('Notu Düzelt'),
            onPressed: () {
              Navigator.pop(ctx);
              _gecmisIadeDuzelt(iade, kalemler);
            },
          ),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _gecmisIadeyiDevamEt(iade);
            },
            child: const Text('Düzenle'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Future<void> _gecmisIadeDuzelt(Map<String, dynamic> iade, List<Map<String, dynamic>> kalemler) async {
    // Düzeltme: sadece not/açıklama ve iade nedeni düzenlenebilir
    final notCtrl = TextEditingController(text: iade['iade_nedeni']?.toString() ?? '');
    // 🔴 DÜZELTME (komple derin analizde bulundu): notCtrl hiç dispose
    // edilmiyordu — dış try/finally ile garanti altına alındı.
    try {
      await _gecmisIadeDuzeltIc(iade, notCtrl);
    } finally {
      dialogSonrasiBirak([notCtrl]);
    }
  }

  Future<void> _gecmisIadeDuzeltIc(
      Map<String, dynamic> iade, TextEditingController notCtrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('İadeyi Düzelt'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('İade nedeni ve notunu düzenleyebilirsiniz.',
              style: TextStyle(fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: notCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'İade Nedeni / Not',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note_alt),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      // Madde 2 sertleştirmesi: doğrudan Veritabani().db erişimi
      // kaldırıldı — IadeDeposu repository katmanı üzerinden yazılıyor
      // (kuyruk kaydı business data ile aynı transaction'da atomik).
      await IadeDeposu().notGuncelle(
        iadeId: iade['id'] as int,
        iadeNedeni: notCtrl.text.trim(),
      );
      if (!mounted) return;
      BildirimServisi.basari(context, 'İade güncellendi ✓');
      _gecmisYukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}
