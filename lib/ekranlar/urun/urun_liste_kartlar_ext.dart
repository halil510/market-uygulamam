// lib/ekranlar/urun/urun_liste_kartlar_ext.dart
// urun_liste_ekrani.dart'ın parçası — liste/ızgara kartı görünümleri
// (god-class sertleştirmesi, 2026-09-22). Davranış birebir korundu.
part of 'urun_liste_ekrani.dart';

extension _UrunListeKartlarExt on _UrunListeEkraniState {
  Widget _FilterChip(String label, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: TsRenk.zemin(TsRenk.bilgi, opaklik: 0.18),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.blue)),
          const SizedBox(width: 4),
          GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 14, color: Colors.blue)),
        ]),
      );

  Widget _listeView(List<UrunModel> urunler, UrunListeDurum durum) =>
      ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
        itemCount: urunler.length + (durum.yukleniyor ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == urunler.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: AppYukleniyor()),
            );
          }
          final u = urunler[i];
          final stokRenk = u.stok <= 0
              ? Colors.red
              : u.kritikStok
                  ? Colors.orange
                  : Colors.green;

          final kart = RepaintBoundary(
            child: TsKart(
              padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
              onLongPress: () =>
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!),
              onTap: () {
                if (durum.secimModu) {
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!);
                } else {
                  context.push('/urun/detay/${u.id}');
                }
              },
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Avatar / resim
                GestureDetector(
                  onTap: () => _resimBuyut(u.resimYolu),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color.fromARGB(
                            46, stokRenk.red, stokRenk.green, stokRenk.blue),
                        Color.fromARGB(
                            15, stokRenk.red, stokRenk.green, stokRenk.blue)
                      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Color.fromARGB(
                              64, stokRenk.red, stokRenk.green, stokRenk.blue)),
                      image: u.resimYolu != null &&
                              u.resimYolu!.isNotEmpty &&
                              File(u.resimYolu!).existsSync()
                          ? DecorationImage(
                              // 🔴 DÜZELTME (performans denetimi):
                              // FileImage tam çözünürlükte decode ediyordu
                              // (kamera fotoğrafı birkaç MB olabilir) —
                              // 64x64'lük bir kutuda gösterilirken bile.
                              // ResizeImage, decode boyutunu gerçek
                              // gösterim boyutuna indirip bellek/jank
                              // riskini ortadan kaldırıyor.
                              image: ResizeImage(
                                FileImage(File(u.resimYolu!)),
                                width: (64 * MediaQuery.of(context).devicePixelRatio).round(),
                                height: (64 * MediaQuery.of(context).devicePixelRatio).round(),
                              ),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: (u.resimYolu == null ||
                            u.resimYolu!.isEmpty ||
                            !File(u.resimYolu!).existsSync())
                        ? Center(
                            child: Text(u.urunAdi[0].toUpperCase(),
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: stokRenk)))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // ORTA — ürün adı + stok + alış + grup
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Ürün adı — uzun isimler için tüm genişlik
                      Text(u.urunAdi,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      // Stok rozeti + Alış fiyatı — isim altında, yan yana
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Color.fromARGB(31, stokRenk.red,
                                  stokRenk.green, stokRenk.blue),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              '${u.stok.toStringAsFixed(u.stok == u.stok.roundToDouble() ? 0 : 1)} ${u.birimAdi}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: stokRenk)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(
                                'Alış: ${ParaUtils.formatla(u.alisFiyatKdvDahil)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: TsRenk.metinIkincil(context)))),
                      ]),
                      if (u.anaGrup != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: TsRenk.zemin(TsRenk.bilgi),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(u.anaGrup!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                      if (_ekAlanlar.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 2, children: [
                          if (_ekAlanlar.contains('barkod') &&
                              u.barkod != null &&
                              u.barkod!.isNotEmpty)
                            Text('Barkod: ${u.barkod}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('marka') &&
                              u.marka != null &&
                              u.marka!.isNotEmpty)
                            Text('Marka: ${u.marka}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('kdv'))
                            Text('KDV: %${u.kdvOran}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('kod') &&
                              u.kod != null &&
                              u.kod!.isNotEmpty)
                            Text('Kod: ${u.kod}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('minStok') &&
                              u.minimumStok > 0)
                            Text(
                                'Min. Stok: ${u.minimumStok.toStringAsFixed(u.minimumStok == u.minimumStok.roundToDouble() ? 0 : 1)}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('karTutari'))
                            Text(
                                'Kâr: ${ParaUtils.formatla(u.satisFiyati - u.alisFiyatKdvDahil)}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('stokDegeri'))
                            Text(
                                'Stok Değeri: ${ParaUtils.formatla(u.stok * u.alisFiyatKdvDahil)}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('rafNo') &&
                              u.rafNumarasi != null &&
                              u.rafNumarasi!.isNotEmpty)
                            Text('Raf: ${u.rafNumarasi}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('uretici') &&
                              u.uretici != null &&
                              u.uretici!.isNotEmpty)
                            Text('Üretici: ${u.uretici}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                        ]),
                      ],
                    ])),
                const SizedBox(width: 10),
                // SAĞ — satış fiyatı + kar + ikonlar
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(ParaUtils.formatla(u.satisFiyati),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: TsRenk.primary)),
                      if (u.karOrani > 0) ...[
                        const SizedBox(height: 3),
                        Text('%${u.karOrani.toStringAsFixed(1)} ▲',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 8),
                      // 2 ikon — aralık genişletildi
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: () => _hizliBilgiGoster(u),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: TsRenk.zemin(TsRenk.bilgi),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.info_outline,
                                size: 19, color: Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            if (u.barkod != null && u.barkod!.isNotEmpty) {
                              _barkodGoster(u.barkod!, u.urunAdi);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: context.borderColor,
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.linear_scale,
                                size: 19,
                                color: u.barkod != null && u.barkod!.isNotEmpty
                                    ? context.textSecondary
                                    : context.borderColor),
                          ),
                        ),
                      ]),
                    ]),
              ]),
            ),
          );
          // Seçim tik — seçim modunda sol üstte her zaman görünen daire
          return Stack(children: [
            kart,
            if (durum.secimModu)
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(urunlerProvider.notifier).secimToggle(u.id!),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: durum.seciliIds.contains(u.id!)
                          ? AppRenkler.primary
                          : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: durum.seciliIds.contains(u.id!)
                              ? AppRenkler.primary
                              : context.textSecondary,
                          width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Color(0x1F000000), blurRadius: 3)
                      ],
                    ),
                    child: durum.seciliIds.contains(u.id!)
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
              ),
          ]);
        },
      );

  Widget _izgaraView(List<UrunModel> urunler, UrunListeDurum durum) =>
      GridView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: TsResponsive.izgaraKolonSayisi(context,
                telefon: 2, tablet: 4, genis: 5),
            childAspectRatio: 0.85,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8),
        itemCount: urunler.length + (durum.yukleniyor ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == urunler.length) {
            return const Center(child: AppYukleniyor());
          }
          final u = urunler[i];
          final stokRenk = u.stok <= 0
              ? Colors.red
              : u.kritikStok
                  ? Colors.orange
                  : Colors.green;
          return RepaintBoundary(
            child: TsKart(
              secili: durum.seciliIds.contains(u.id!),
              onLongPress: () =>
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!),
              onTap: () {
                if (durum.secimModu) {
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!);
                } else {
                  context.push('/urun/detay/${u.id}');
                }
              },
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => _resimBuyut(u.resimYolu),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: Color.fromARGB(26, stokRenk.red,
                                      stokRenk.green, stokRenk.blue),
                                  borderRadius: BorderRadius.circular(12),
                                  image: u.resimYolu != null &&
                                          u.resimYolu!.isNotEmpty &&
                                          File(u.resimYolu!).existsSync()
                                      ? DecorationImage(
                                          // bkz. yukarıdaki liste-modu notu — aynı düzeltme
                                          image: ResizeImage(
                                            FileImage(File(u.resimYolu!)),
                                            width: (48 * MediaQuery.of(context).devicePixelRatio).round(),
                                            height: (48 * MediaQuery.of(context).devicePixelRatio).round(),
                                          ),
                                          fit: BoxFit.cover)
                                      : null),
                              child: (u.resimYolu == null ||
                                      u.resimYolu!.isEmpty ||
                                      !File(u.resimYolu!).existsSync())
                                  ? Center(
                                      child: Text(u.urunAdi[0].toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: stokRenk)))
                                  : null,
                            ),
                          ),
                          if (u.barkod != null && u.barkod!.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.qr_code_2,
                                  size: 18, color: Colors.blue),
                              onPressed: () =>
                                  _barkodGoster(u.barkod!, u.urunAdi),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ]),
                    const SizedBox(height: 8),
                    Text(u.urunAdi,
                        style: TsMetin.govdeVurgu,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    Text(ParaUtils.formatla(u.satisFiyati),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Color.fromARGB(
                              31, stokRenk.red, stokRenk.green, stokRenk.blue),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('${u.stok.toStringAsFixed(0)} ${u.birimAdi}',
                          style: TsMetin.kucukVurgu.copyWith(color: stokRenk)),
                    ),
                  ]),
            ),
          );
        },
      );
}
