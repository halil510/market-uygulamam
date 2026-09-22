// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: Bu dosya `part of 'urun_liste_ekrani.dart'` ve içeriği
// `extension ... on _UrunListeEkraniState` olarak yazılmış — projenin
// diğer ekranlarında zaten kullanılan, ÇALIŞAN bir desen (bkz.
// iade_ekrani_hizli.dart). Dart analizcisi `setState`'i @protected
// gördüğü için, extension içinden çağrıyı "korumalı üyeye dışarıdan
// erişim" sayıyor. Derlemeyi engellemez; sadece analiz uyarısıdır.
// lib/ekranlar/urun/urun_liste_dialoglar_ext.dart
// urun_liste_ekrani.dart'ın parçası — görünüm tercihi, hızlı bilgi,
// toplu silme, barkod arama/gösterme, Excel aktarım, filtre sheet
// diyalogları (god-class sertleştirmesi, 2026-09-22). Davranış birebir
// korundu.
part of 'urun_liste_ekrani.dart';

extension _UrunListeDialoglarExt on _UrunListeEkraniState {
  Future<void> _gorunumTercihiYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kayitli = prefs.getStringList('urun_liste_ek_alanlar');
      if (kayitli != null && mounted) {
        setState(() => _ekAlanlar = kayitli.toSet());
      }
    } catch (_) {
      // Tercih okunamazsa varsayılan (boş) görünümle devam edilir.
    }
  }

  Future<void> _gorunumTercihiKaydet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('urun_liste_ek_alanlar', _ekAlanlar.toList());
    } catch (_) {
      // Kaydedilemezse sessizce geçilir — bir sonraki açılışta varsayılana döner.
    }
  }

  Future<void> _gorunumSecimiAc() async {
    var secim = Set<String>.from(_ekAlanlar);
    final sonuc = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Kartta Gösterilecek Alanlar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in _UrunListeEkraniState._ekAlanEtiketleri.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: secim.contains(e.key),
                  onChanged: (v) => ss(() {
                    if (v == true) {
                      secim.add(e.key);
                    } else {
                      secim.remove(e.key);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, secim),
                child: const Text('Uygula')),
          ],
        );
      }),
    );
    if (sonuc != null && mounted) {
      setState(() => _ekAlanlar = sonuc);
      _gorunumTercihiKaydet();
    }
  }

  void _hizliBilgiGoster(UrunModel u) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(u.urunAdi, style: const TextStyle(fontSize: 15)),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (u.barkod != null) _bilgiSatir('Barkod', u.barkod!),
                    _bilgiSatir(
                        'Satış Fiyatı', ParaUtils.formatla(u.satisFiyati)),
                    _bilgiSatir('Alış Fiyatı', ParaUtils.formatla(u.alisFiyat)),
                    _bilgiSatir('KDV', '%${u.kdvOran}'),
                    _bilgiSatir('Stok', '${u.stok} ${u.birimAdi}'),
                    if (u.anaGrup != null) _bilgiSatir('Grup', u.anaGrup!),
                    if (u.marka != null) _bilgiSatir('Marka', u.marka!),
                    _bilgiSatir(
                        'Kar Oranı', '%${u.karOrani.toStringAsFixed(1)}'),
                  ]),
              actions: [
                const BulutDurumIkonu(),
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/urun/detay/${u.id}');
                    },
                    child: const Text('Detay')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat')),
              ],
            ));
  }

  Widget _bilgiSatir(String etiket, String deger) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 90,
            child: Text(etiket,
                style: TextStyle(
                    fontSize: 12, color: TsRenk.metinIkincil(context)))),
        Expanded(
            child: Text(deger,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
      ]));

  Future<void> _seciliUrunleriSil(Set<int> ids) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Toplu Silme'),
        content: Text('${ids.length} ürün silinecek. Onaylıyor musunuz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    // 🔴 Derin denetimde bulundu (P2): döngü try/catch'siz — N üründen
    // biri hata verirse döngü kesiliyordu, secimTemizle() ve başarı
    // mesajı hiç çalışmıyordu, kullanıcı hangi ürünlerin silindiğini
    // bilemiyordu. Artık her ürün kendi try/catch'inde: bir hata
    // diğerlerini engellemiyor, sonunda ne kadarının silindiği/
    // silinemediği açıkça bildiriliyor.
    var silinen = 0;
    var hatali = 0;
    for (final id in ids) {
      try {
        await ref.read(urunlerProvider.notifier).sil(id);
        silinen++;
      } catch (e) {
        hatali++;
      }
    }
    ref.read(urunlerProvider.notifier).secimTemizle();
    if (!mounted) return;
    if (hatali == 0) {
      basariMesaji(context, '$silinen ürün silindi');
    } else {
      hataMesaji(context, '$silinen ürün silindi, $hatali ürün silinemedi');
    }
  }

  // ── Barkod ile arama ──────────────────────────────────────────────────────
  Future<void> _barkodIleAra() async {
    try {
      final barkod = await _barkodSrv.barkodTara(context);
      if (barkod == null || !mounted) return;

      // Direkt DB'den barkodla ara (barkod ve barkodlar alanları)
      final urun = await UrunDeposu().barkodlaGetir(barkod);
      if (!mounted) return;

      if (urun != null) {
        // Bulundu — listede göster
        _araCtrl.text = barkod;
        ref.read(urunFiltresiProvider.notifier).aramaGuncelle(barkod);
      } else {
        // Bulunamadı — direkt ürün ekle ekranına git
        final ok = await context.push<bool>(
          '/urun/ekle',
          extra: {'barkod': barkod, 'kaynak': 'urun_liste'},
        );
        if (ok == true && mounted) {
          _araCtrl.clear();
          ref.read(urunlerProvider.notifier).yukle(sifirla: true);
        }
      }
    } catch (e) {
      if (kDebugMode && mounted) debugPrint('Hata: $e');
    }
  }

  // ── Resim büyüt ───────────────────────────────────────────────────────────
  void _resimBuyut(String? resimYolu) {
    if (resimYolu == null || resimYolu.isEmpty) return;
    final file = File(resimYolu);
    if (!file.existsSync()) return;
    showDialog(
      context: context,
      builder: (bCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(alignment: Alignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(bCtx),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Barkod göster dialog ─────────────────────────────────────────────────
  void _barkodGoster(String barkod, String urunAdi) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(urunAdi,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: barkod,
              width: 220,
              height: 80,
              drawText: true,
            ),
            const SizedBox(height: 16),
            Text(barkod,
                style: const TextStyle(fontSize: 13, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: barkod));
                Navigator.pop(ctx);
              },
              child: const Text('Kopyala & Kapat'),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Excel aktar ───────────────────────────────────────────────────────────
  Future<void> _excelAktar({bool sutunSec = false}) async {
    final durum = ref.read(urunlerProvider);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Ürünler'];
      sheet.appendRow([
        TextCellValue('Ürün Adı'),
        TextCellValue('Barkod'),
        TextCellValue('Stok'),
        TextCellValue('Alış'),
        TextCellValue('Satış'),
        TextCellValue('Birim'),
        TextCellValue('Grup'),
      ]);
      for (final u in durum.urunler) {
        sheet.appendRow([
          TextCellValue(excelIcinGuvenliMetin(u.urunAdi)),
          TextCellValue(excelIcinGuvenliMetin(u.barkod)),
          DoubleCellValue(u.stok),
          DoubleCellValue(u.alisFiyat),
          DoubleCellValue(u.satisFiyati),
          TextCellValue(u.birimAdi),
          TextCellValue(excelIcinGuvenliMetin(u.anaGrup)),
        ]);
      }
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/urunler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(excel.encode()!);
      await Share.shareXFiles([XFile(path)], text: 'Ürün Listesi');
    } catch (e) {
      if (mounted) hataMesaji(context, 'Excel hatası: $e');
    }
  }

  // ── Filtre sheet ──────────────────────────────────────────────────────────
  Future<void> _filtreSheet() async {
    final durum = ref.read(urunlerProvider);
    final filtre = ref.read(urunFiltresiProvider);
    final gruplar = durum.urunler
        .map((u) => u.anaGrup ?? '')
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    const siralamaSecenekleri = [
      ('isim', 'İsim (A-Z)'),
      ('stok_azalan', 'Stok (Çoktan Aza)'),
      ('stok_artan', 'Stok (Azdan Çoka)'),
      ('guncelleme_yeni', 'En Son Güncellenen'),
      ('fiyat_yuksek', 'Satış Fiyatı (Yüksekten Düşüğe)'),
      ('fiyat_dusuk', 'Satış Fiyatı (Düşükten Yükseğe)'),
      ('grup', 'Gruba Göre'),
      ('alan1', 'Alan 1\'e Göre'),
    ];

    // 🔥 ÖNCEDEN BURADAKİ HATA: kritikOnly/tmpSiralama/tmpGrup
    // StatefulBuilder'ın builder FONKSİYONUNUN İÇİNDE tanımlıydı — bu,
    // klasik bir Flutter hatası: ss() (setState) her çağrıldığında
    // builder fonksiyonu BAŞTAN çalışıyor, bu üç değişken de HER
    // SEFERİNDE orijinal (filtre.xxx) değerine SIFIRLANIYORDU. Yani
    // bir sıralama seçeneğine dokunduğunuzda görsel olarak an be an
    // değişiyor gibi görünse de, "Uygula"ya bastığınızda değişken
    // ZATEN sıfırlanmış oluyordu — kullanıcının bildirdiği "filtreleme
    // yapmıyor" hatası tam olarak buydu. Artık bu üç değişken
    // StatefulBuilder'ın DIŞINDA tanımlanıyor, rebuild'lerden
    // ETKİLENMİYOR.
    bool kritikOnly = filtre.sadecKritikler ?? false;
    String tmpSiralama = filtre.siralama;
    String? tmpGrup = filtre.grupFiltre;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 🔥 ÖNCEDEN arkaplan rengi belirtilmiyordu (varsayılan beyaz
      // geliyordu) ve metinler de renk belirtmeden (varsayılan tema
      // rengiyle) yazılmıştı — karanlık modda "beyaz üzerine beyaz"
      // gibi okunmaz bir görüntü oluşabiliyordu. Artık uygulamanın
      // kendi tema-farkında renkleri (context.cardBg, textPrimary vb.)
      // kullanılıyor, hem açık hem karanlık modda net okunuyor.
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Filtrele ve Sırala',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary)),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text('Sadece Kritik Stok',
                    style: TextStyle(color: context.textPrimary)),
                value: kritikOnly,
                onChanged: (v) => ss(() => kritikOnly = v),
              ),
              Divider(height: 24, color: context.dividerColor),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sıralama',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (deger, etiket) in siralamaSecenekleri)
                  ChoiceChip(
                    label: Text(etiket,
                        style: TextStyle(
                            fontSize: 12,
                            color: tmpSiralama == deger
                                ? Colors.white
                                : context.textPrimary)),
                    selected: tmpSiralama == deger,
                    backgroundColor: context.inputFill,
                    onSelected: (_) => ss(() => tmpSiralama = deger),
                  ),
              ]),
              if (gruplar.isNotEmpty) ...[
                Divider(height: 24, color: context.dividerColor),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Grup',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: tmpGrup,
                  dropdownColor: context.cardBg,
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: context.inputFill,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10)),
                  hint: Text('Tüm Gruplar',
                      style: TextStyle(color: context.textHint)),
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text('Tüm Gruplar',
                            style: TextStyle(color: context.textPrimary))),
                    for (final g in gruplar)
                      DropdownMenuItem(
                          value: g,
                          child: Text(g,
                              style: TextStyle(color: context.textPrimary))),
                  ],
                  onChanged: (v) => ss(() => tmpGrup = v),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                  onPressed: () {
                    ref.read(urunFiltresiProvider.notifier).sifirla();
                    ref.read(urunlerProvider.notifier).yukle(sifirla: true);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Temizle'),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                  onPressed: () {
                    final notifier = ref.read(urunFiltresiProvider.notifier);
                    if (kritikOnly != (filtre.sadecKritikler ?? false)) {
                      notifier.kritikToggle();
                    }
                    notifier.siralamaGuncelle(tmpSiralama);
                    notifier.grupGuncelle(tmpGrup);
                    ref.read(urunlerProvider.notifier).yukle(sifirla: true);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Uygula'),
                )),
              ]),
            ]),
          ),
        );
      }),
    );
  }
}
