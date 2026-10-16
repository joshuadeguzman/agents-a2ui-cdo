import 'package:flutter_test/flutter_test.dart';
import 'package:siargao_genui/catalog/binding.dart';
import 'package:siargao_genui/features/chat/plain_text_view.dart';

void main() {
  test('headings and bold lines keep their last two words together', () {
    expect(
      gluePhraseEnds('## Your first trip\n\nBody text here\n**Day 1: Land**'),
      '## Your first\u00A0trip\n\nBody text here\n**Day 1:\u00A0Land**',
    );
  });

  test('noWidow glues short tails only', () {
    expect(noWidow('Book this plan'), 'Book this\u00A0plan');
    expect(noWidow('Choose'), 'Choose');
    expect(noWidow('Two words'), 'Two words');
  });

  test('money is formatted with the ISO code', () {
    expect(formatMoney(24900), 'PHP 24,900');
    expect(formatMoney(12.5, currency: 'usd'), 'USD 12.50');
  });
}
