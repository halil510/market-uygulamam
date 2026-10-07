// test/servisler/bulut_fk_hedefli_sorgu_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07), Bulgu 9 — FK dönüşümü artık
// ebeveyn tablonun tamamını değil yalnız gereken anahtarları sorgular.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/bulut/supabase_saglayici.dart';

void main() {
  test('in.() filtresi değerleri tırnaklar, virgül/tırnak içerenleri kaçışlar', () {
    expect(SupabaseSaglayici.inFiltresi(['a1', 'b2']), 'in.("a1","b2")');
    expect(SupabaseSaglayici.inFiltresi(['Süt, Peynir']), 'in.("Süt, Peynir")');
    expect(SupabaseSaglayici.inFiltresi([r'a"b\c']), r'in.("a\"b\\c")');
  });

  test('parça boyutu URL sınırına uygun', () {
    expect(SupabaseSaglayici.fkSorguParcasi, inInclusiveRange(1, 100));
  });

  test('sorgu adresi kodlanmış ve yalnız istenen anahtarları içerir', () {
    final uri = Uri.parse('https://x.supabase.co/rest/v1/satislar').replace(
        queryParameters: {
          'select': 'id,global_id',
          'global_id': SupabaseSaglayici.inFiltresi(['u-1', 'u-2']),
        });
    expect(uri.queryParameters['global_id'], 'in.("u-1","u-2")');
    expect(uri.toString(), isNot(contains('offset')));
  });
}
