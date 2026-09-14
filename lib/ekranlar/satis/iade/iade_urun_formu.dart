// lib/ekranlar/satis/iade/iade_urun_formu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../modeller/urun_model.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';

class IadeUrunFormu extends StatelessWidget {
  final UrunModel urun;
  final TextEditingController miktarCtrl;
  final TextEditingController fiyatCtrl;
  final TextEditingController iskontoCtrl;
  final double miktar;
  final double orijinalFiyat;
  final VoidCallback onSifirla;
  final VoidCallback onDegisti;
  final String odemeYontemi;
  final ValueChanged<String> onOdemeYontemiChanged;

  const IadeUrunFormu({
    super.key,
    required this.urun,
    required this.miktarCtrl,
    required this.fiyatCtrl,
    required this.iskontoCtrl,
    required this.miktar,
    required this.orijinalFiyat,
    required this.onSifirla,
    required this.onDegisti,
    required this.odemeYontemi,
    required this.onOdemeYontemiChanged,
  });

  // Ana iade_ekrani.dart'taki _R paletiyle aynı TsRenk semantik sabitleri
  // kullanılıyor — önceden burada farklı, sabit bir turuncu tonu vardı ve
  // ekranın geri kalanıyla (İade Et butonu, sekme göstergesi) renk uyumsuzdu.
  static const _orange = TsRenk.uyari;
  static const _green = TsRenk.basarili;
  static const _red = TsRenk.hata;

  double get _fiyat => ParaUtils.sayiCoz(fiyatCtrl.text) ?? orijinalFiyat;
  double get _iskonto => ParaUtils.sayiCoz(iskontoCtrl.text) ?? 0;
  double get _araToplam => miktar * _fiyat;
  double get _net => _araToplam * (1 - _iskonto / 100);

  @override
  Widget build(BuildContext context) {
    // ÖNCEDEN BURADA CİDDİ BİR KARANLIK MOD HATASI VARDI (bkz.
    // iade_gecmis_widget.dart'taki aynı düzeltme) — sabit koyu/açık metin
    // renkleri karanlık modda neredeyse görünmez oluyordu.
    final textD = TsRenk.metinBirincil(context);
    final textL = TsRenk.metinIkincil(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Başlık
        Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: _orange.withAlpha(26),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.inventory_2_outlined,
                  color: _orange, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(urun.urunAdi,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textD)),
                Text(urun.barkod ?? '',
                    style: TextStyle(fontSize: 12, color: textL)),
              ])),
          IconButton(
              icon: Icon(Icons.close, color: textL), onPressed: onSifirla),
        ]),
        const Divider(height: 24),
        // Fiyat / Stok
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Normal Satış Fiyatı',
                    style: TextStyle(fontSize: 11, color: textL)),
                Text(ParaUtils.formatla(urun.satisFiyati),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textD)),
              ])),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Mevcut Stok',
                    style: TextStyle(fontSize: 11, color: textL)),
                Text(urun.stok.toStringAsFixed(0),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: urun.stok <= 0 ? _red : _green)),
              ])),
        ]),
        const SizedBox(height: 16),
        // Miktar + Fiyat
        Row(children: [
          Expanded(
              child: TextField(
            controller: miktarCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            onChanged: (_) => onDegisti(),
            decoration: const InputDecoration(
                labelText: 'İade Miktarı',
                prefixIcon: Icon(Icons.production_quantity_limits, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
                isDense: true),
          )),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                TextField(
                  controller: fiyatCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  onChanged: (_) => onDegisti(),
                  decoration: const InputDecoration(
                      labelText: 'Birim Fiyat (₺)',
                      prefixIcon: Icon(Icons.attach_money, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10))),
                      isDense: true),
                ),
                const SizedBox(height: 4),
                // Kullanıcı isteği: "istediğimde alış istediğimde satış
                // fiyatı gelsin" — cari tipine göre otomatik varsayılan
                // geliyor, ama artık kullanıcı istediği zaman tek dokunuşla
                // diğer fiyata geçebiliyor.
                Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () {
                      fiyatCtrl.text = urun.satisFiyat.toStringAsFixed(2);
                      onDegisti();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _green.withAlpha(25),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          'Satış: ${urun.satisFiyat.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: _green,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      fiyatCtrl.text = urun.alisFiyat.toStringAsFixed(2);
                      onDegisti();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _orange.withAlpha(25),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('Alış: ${urun.alisFiyat.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: _orange,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ])),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: iskontoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
          ],
          onChanged: (_) => onDegisti(),
          decoration: InputDecoration(
            labelText: 'İskonto % (0-100)',
            prefixIcon: const Icon(Icons.percent, size: 18),
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
            isDense: true,
            suffixText: '%',
            helperText: 'İskonto uygulamak için doldurun',
            helperStyle: const TextStyle(fontSize: 10),
            filled: true,
            fillColor: _orange.withAlpha(18),
          ),
        ),
        const SizedBox(height: 12),
        // İade Ödeme Yöntemi — bu manuel akışta orijinal satışa bağlantı
        // olmadığından varsayılan Nakit, kullanıcı Kart/Banka'ya çevirebilir.
        // Kart/Banka seçilirse kasa_hareketleri'ne hiç yazılmaz (bkz. iade_ekrani.dart _kaydet).
        DropdownButtonFormField<String>(
          initialValue: odemeYontemi,
          decoration: const InputDecoration(
            labelText: 'İade Ödeme Yöntemi',
            prefixIcon: Icon(Icons.payments_outlined, size: 18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(
                value: 'Nakit', child: Text('Nakit (kasadan ödenir)')),
            DropdownMenuItem(
                value: 'Kart/Banka', child: Text('Kart/Banka (POS üzerinden)')),
          ],
          onChanged: (v) {
            if (v != null) onOdemeYontemiChanged(v);
          },
        ),
        if (odemeYontemi != 'Nakit') ...[
          const SizedBox(height: 6),
          Text(
            'Bu tutar kasadan nakit çıkışı olarak kaydedilmeyecek. Müşteriye iadeyi POS cihazından ayrıca yapmanız gerekir.',
            style: TextStyle(
                fontSize: 11,
                color: _orange,
                fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 12),
        // Özet
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _orange.withAlpha(15),
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Ara Toplam:', style: TextStyle(fontSize: 12, color: textL)),
              Text(ParaUtils.formatla(_araToplam),
                  style: TextStyle(fontSize: 13, color: textL)),
            ]),
            if (_iskonto > 0) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('İskonto (${iskontoCtrl.text}%):',
                    style: const TextStyle(fontSize: 12, color: _orange)),
                Text('- ${ParaUtils.formatla(_araToplam * _iskonto / 100)}',
                    style: const TextStyle(fontSize: 12, color: _orange)),
              ]),
            ],
            const Divider(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('İade Toplam:',
                  style: TextStyle(fontSize: 13, color: textL)),
              Text(ParaUtils.formatla(_net),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _orange)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
