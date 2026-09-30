// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/satis/hizli_satis_ekrani_masaustu.dart
// hizli_satis_ekrani.dart'ın parçası. Geniş (masaüstü) pencerede kullanılan
// düzeni kurar; görünüm masaustu/ klasöründeki küçük widget'lardadır, iş
// mantığı (ödeme, sepete ekleme, müşteri seçimi) bu sınıftaki mevcut
// metotlardan geri-çağrı olarak bağlanır.
part of 'hizli_satis_ekrani.dart';

/// Bu genişliğin üstünde BarkoPOS benzeri masaüstü düzeni kullanılır.
const double _masaustuEsigi = 1000;

extension _HizliSatisMasaustuExt on _HizliSatisEkraniState {
  Widget _masaustuDuzen() => MasaustuHizliSatisDuzeni(
        aramaPaneli: _aramaPaneli(),
        aramaSonuclari:
            _aramaSonuclari.isNotEmpty ? _aramaSonucListesi() : null,
        sepetScroll: _sepetScroll,
        onUrunSec: _masaustuUrunSec,
        onKalemDuzenle: _sepetKalemMiktarDuzenle,
        onOdeme: _odemeYontemiSec,
        onAramaOdak: () => _araFocus.requestFocus(),
        onStok: () => context.push('/stok'),
        onAskiyaAl: _askiyaAl,
        onSonFis: _sonSatis == null ? null : _sonFisiYazdir,
        onCari: _musteriSec,
        onFiyatGor: () => context.push('/fiyat-gor'),
      );

  /// Ürün tuşuna basış — bottom-sheet sürümüyle (_hizliTusAc) aynı mantık.
  Future<void> _masaustuUrunSec(UrunModel urun) async {
    if (_kgBirimMi(urun.birimAdi)) {
      await _kgIleEkle(urun);
    } else {
      await ref.read(sepetProvider.notifier).ekleAsync(urun);
    }
    if (!mounted) return;
    _bipSes();
    if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
  }

  Future<void> _sonFisiYazdir() async {
    final satis = _sonSatis;
    if (satis == null) return;
    try {
      await YazdirmaServisi().fisYazdir(satis);
      if (!mounted) return;
      BildirimServisi.basari(context, 'Fiş yazdırılıyor…');
    } catch (e) {
      if (!mounted) return;
      BildirimServisi.hata(context, 'Yazdırılamadı: $e');
    }
  }
}
