import unittest
from organizar_canais_importados import consolidate, normalized, is_open_channel


def channel(name, category='Filmes e Séries', source='https://example.test/original'):
    return f'canal: {name}\ncategoria: {category}\nfonte: {source}\nqualidade: HD\n\n'


class CatalogCleanupTests(unittest.TestCase):
    def test_alias_keeps_sources_metadata_and_order(self):
        old = channel('Warner')
        addition = channel('Warner Channel', source='https://example.test/new')+'referer: https://example.test/\n'
        result, report = consolidate(old+addition, old)
        self.assertEqual(result.count('canal: '), 1)
        self.assertIn('referer: https://example.test/', result)
        self.assertLess(result.index('/original'), result.index('/new'))
        self.assertEqual(len(report['duplicados_unificados']), 1)

    def test_only_new_open_channels_are_removed(self):
        old = channel('Globo SP', 'TV Aberta')
        current = old+channel('Globo EPTV Campinas', 'TV Aberta')+channel('Globo TV Verdes Mares', 'Variedades')
        result, report = consolidate(current, old)
        self.assertEqual(result.strip(), old.strip())
        self.assertEqual(len(report['abertos_novos_removidos']), 2)

    def test_distinct_channels_are_not_fuzzy_merged(self):
        old = channel('CNBC')+channel('SportyNet+ 1')
        current = old+channel('CNBC Brasil')+channel('SportyNet 1')
        result, report = consolidate(current, old)
        self.assertEqual(result.count('canal: '), 4)
        self.assertFalse(report['duplicados_unificados'])
        self.assertNotEqual(normalized('SportyNet 1'), normalized('SportyNet+ 1'))

    def test_number_format_and_idempotence(self):
        old = channel('MAX 01')
        result, report = consolidate(old+channel('Max 1',source='https://example.test/reserve'),old)
        again, second = consolidate(result,old)
        self.assertEqual(result,again)
        self.assertEqual(len(report['duplicados_unificados']),1)
        self.assertFalse(second['duplicados_unificados'])

    def test_news_not_mistaken_for_open_affiliate(self):
        self.assertFalse(is_open_channel('GloboNews','Notícias'))
        self.assertTrue(is_open_channel('Globo TV Verdes Mares','Variedades'))


if __name__ == '__main__':
    unittest.main()
