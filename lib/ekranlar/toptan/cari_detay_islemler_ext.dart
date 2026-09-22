// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: Bu dosya `part of 'cari_detay_paneli.dart'` ve içeriği
// `extension ... on _CariDetayPaneliState` olarak yazılmış — projenin
// diğer ekranlarında zaten kullanılan, ÇALIŞAN bir desen (bkz.
// iade_ekrani_hizli.dart). Dart analizcisi `setState`'i @protected
// gördüğü için, extension içinden çağrıyı "korumalı üyeye dışarıdan
// erişim" sayıyor. Derlemeyi engellemez; sadece analiz uyarısıdır.
// lib/ekranlar/toptan/cari_detay_islemler_ext.dart
// cari_detay_paneli.dart'ın parçası — "İŞLEMLER" sekmesi (Satışlar/
// Faturalar/Tahsilatlar alt listeleri) (god-class sertleştirmesi,
// 2026-09-22). Davranış birebir korundu.
part of 'cari_detay_paneli.dart';

extension _CariDetayIslemlerExt on _CariDetayPaneliState {
  // ══════════════════ 1) İŞLEMLER (Logo: fiş türü seçip işlem yap) ══════
  Widget _islemlerSekmesi() {
    return Column(children: [
      // Hızlı işlem butonları (Logo'nun "işlemler sekmesi altından fiş
      // türü seçilerek işlem yapılır" mantığı).
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.6,
          children: [
            _islemKisayolu('Yeni Satış', Icons.add_shopping_cart, AppRenkler.primary, _yeniSatis),
            _islemKisayolu('Sipariş Al', Icons.playlist_add_check_circle_outlined, Colors.deepPurple, _siparisAl),
            _islemKisayolu('Bekleyen Siparişler', Icons.pending_actions_outlined, Colors.orange, _bekleyenSiparisler),
            _islemKisayolu('Toptan Ürünler', Icons.inventory_2_outlined, Colors.teal,
                () => context.push('/toptan/urunler')),
          ],
        ),
      ),
      // Alt seçim: hangi fiş listesi gösterilsin (Satışlar/Faturalar/Tahsilatlar).
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'Satışlar', label: Text('Satışlar (${_satislar.length})')),
            ButtonSegment(value: 'Faturalar', label: Text('Faturalar (${_faturalar.length})')),
            ButtonSegment(value: 'Tahsilatlar', label: Text('Tahsilat (${_tahsilatlar.length})')),
          ],
          selected: {_islemAlt},
          onSelectionChanged: (s) => setState(() => _islemAlt = s.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: switch (_islemAlt) {
          'Faturalar' => _faturalarSekmesi(),
          'Tahsilatlar' => _tahsilatlarSekmesi(),
          _ => _satislarSekmesi(),
        },
      ),
    ]);
  }

  Widget _islemKisayolu(String etiket, IconData ikon, Color renk, VoidCallback onTap) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Icon(ikon, color: renk, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(etiket, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }

  // ══════════════════ SATIŞLAR (Cari Ekstre) ══════════════════
  Widget _satislarSekmesi() {
    if (_satislar.isEmpty) return Center(child: Text('Henüz satış yok', style: TextStyle(color: context.textHint)));
    double bakiyeIz = widget.cari.bakiye;
    final bakiyeler = <double>[];
    for (final s in _satislar) {
      bakiyeler.add(bakiyeIz);
      bakiyeIz -= s.genelToplam;
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.dividerColor),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            _ekstreBaslik('TARİH', flex: 3),
            _ekstreBaslik('BELGE NO', flex: 3),
            _ekstreBaslik('TUTAR', flex: 3, sagaYasla: true),
            _ekstreBaslik('BAKİYE', flex: 3, sagaYasla: true),
            const SizedBox(width: 26),
          ]),
        ),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: context.dividerColor),
              right: BorderSide(color: context.dividerColor),
              bottom: BorderSide(color: context.dividerColor),
            ),
          ),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _satislar.length,
            itemBuilder: (c, i) {
              final s = _satislar[i];
              final ciftMi = i.isEven;
              return Column(children: [
                InkWell(
                  // Kullanıcı isteği: "alt panel değil yandan açılır
                  // olacak, profesyoneller gibi." Satıra dokununca
                  // YENİ bir yandan panel (drill-down / stacked
                  // master-detail) açılıyor — İade/Faturalandır/
                  // Çoğalt gibi işlemler ORADA, düzgün boyutlu
                  // butonlar olarak duruyor. Satırın kendisi artık
                  // sıkışık ikonlarla dolu değil.
                  onTap: () async {
                    await satisIslemPaneliAc(
                      context, s, widget.cari,
                      onDetay: () => _detayaGit(s),
                      onFaturalandir: () => _faturalandir(s),
                      onIadeEt: () => _iadeEt(s),
                      onCogalt: () => _cogalt(s),
                      onSil: () => _silmeyeCalis(s),
                    );
                    _yukle();
                  },
                  child: Container(
                    color: ciftMi ? context.inputFill.withAlpha(120) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                    child: Row(children: [
                      _ekstreHucre(DateFormat('dd.MM.yy\nHH:mm').format(s.tarih), flex: 3),
                      _ekstreHucre(s.fisNo ?? '—', flex: 3, sonuk: true),
                      _ekstreHucre(ParaUtils.formatla(s.genelToplam), flex: 3, sagaYasla: true, kalin: true),
                      _ekstreHucre(ParaUtils.formatla(bakiyeler[i]), flex: 3, sagaYasla: true,
                          renk: bakiyeler[i] > 0 ? Colors.red.shade400 : Colors.green.shade600),
                      Icon(Icons.chevron_right, size: 18, color: context.textHint),
                    ]),
                  ),
                ),
                if (i < _satislar.length - 1) Divider(height: 1, color: context.dividerColor),
              ]);
            },
          ),
        ),
      ),
    ]);
  }

  // ══════════════════ FATURALAR ══════════════════
  Widget _faturalarSekmesi() {
    if (_faturalar.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.description_outlined, size: 44, color: context.textHint),
        const SizedBox(height: 8),
        Text('Bu cariye ait fatura yok', style: TextStyle(color: context.textHint)),
        const SizedBox(height: 4),
        Text('Satışlar sekmesinden bir satışı faturalandırabilirsiniz',
            style: TextStyle(fontSize: 12, color: context.textHint)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      itemCount: _faturalar.length,
      itemBuilder: (c, i) {
        final f = _faturalar[i];
        final (renk, etiket) = switch (f.odemeDurumu) {
          'odendi' => (Colors.green, 'Ödendi'),
          'kısmen' => (Colors.orange, 'Kısmi Ödeme'),
          _ => (Colors.red, 'Beklemede'),
        };
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () => context.push('/fatura/detay/${f.id}'),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: renk.withAlpha(30), shape: BoxShape.circle),
                child: Icon(Icons.description_outlined, color: renk, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.faturaNo ?? '—', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
                  Text(DateFormat('dd.MM.yyyy').format(f.tarih), style: TextStyle(fontSize: 11, color: context.textHint)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(ParaUtils.formatla(f.genelToplam), style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: renk.withAlpha(30), borderRadius: BorderRadius.circular(6)),
                  child: Text(etiket, style: TextStyle(fontSize: 9.5, color: renk, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  // ══════════════════ TAHSİLATLAR ══════════════════
  Widget _tahsilatlarSekmesi() {
    if (_tahsilatlar.isEmpty) {
      return Center(child: Text('Bu cariden henüz tahsilat yapılmamış', style: TextStyle(color: context.textHint)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      itemCount: _tahsilatlar.length,
      itemBuilder: (c, i) {
        final t = _tahsilatlar[i];
        final tutar = t.alacak > 0 ? t.alacak : t.borc;
        final iptalMi = t.fisTipi.contains('İptal');
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: (iptalMi ? context.textSecondary : Colors.green).withAlpha(30), shape: BoxShape.circle),
              child: Icon(iptalMi ? Icons.undo : Icons.payments_outlined,
                  color: iptalMi ? context.textSecondary : Colors.green, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.odemeTuru ?? t.fisTipi, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
                Text(DateFormat('dd.MM.yyyy HH:mm').format(t.tarih), style: TextStyle(fontSize: 11, color: context.textHint)),
                if (t.aciklama.isNotEmpty)
                  Text(t.aciklama, style: TextStyle(fontSize: 11, color: context.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Text(ParaUtils.formatla(tutar),
                style: TextStyle(fontWeight: FontWeight.w700, color: iptalMi ? context.textSecondary : Colors.green)),
          ]),
        );
      },
    );
  }

  Widget _ekstreBaslik(String metin, {required int flex, bool sagaYasla = false}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text(metin, textAlign: sagaYasla ? TextAlign.right : TextAlign.left,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: context.textHint)),
        ),
      );

  Widget _ekstreHucre(String metin, {required int flex, bool sagaYasla = false, bool kalin = false, bool sonuk = false, Color? renk}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(metin, textAlign: sagaYasla ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
                color: renk ?? (sonuk ? context.textSecondary : context.textPrimary),
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      );
}
