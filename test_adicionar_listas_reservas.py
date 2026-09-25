import collections
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import substituir_reservas_m3u as importer
from adicionar_listas_reservas import clean_live, normalized


class ReserveImportTests(unittest.TestCase):
    def run_import(self,movies='',series='',entries=()):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'vod').mkdir()
            for file,text in {'catalogo.txt':'','restritos.txt':'','vod/indice.txt':'base: 0 https://example.test/movie/\n',
                              'vod/filmes-A.txt':movies,'vod/series-A-0.txt':series}.items():
                (root/file).write_text(text)
            updates={};counts=collections.Counter()
            with patch.object(importer,'ROOT',root):
                importer.incorporar_novos(list(entries),updates,{'0':'https://example.test/movie/','1':'https://new.test/movie/'},counts)
            return {str(p.relative_to(root)):t for p,t in updates.items()},counts

    @staticmethod
    def entry(title,kind='movie'):
        return {'name':title,'kind':kind,'url':'https://new.test/movie/2.mp4','group':'','logo':''}

    def test_movie_without_year_uses_unique_existing_title(self):
        result,c=self.run_import('A Test (2025)\tdub=0:1\n',entries=[self.entry('A Test')])
        self.assertIn('A Test (2025)\tdub=0:1,1:2',result['vod/filmes-A.txt'])
        self.assertEqual(c['novos_filmes'],0)

    def test_ambiguous_remakes_not_merged(self):
        result,c=self.run_import('A Test (1987)\tdub=0:1\nA Test (2026)\tdub=0:3\n',entries=[self.entry('A Test')])
        self.assertEqual(c['filmes_ambiguos_ignorados'],1)
        self.assertNotIn('1:2',result['vod/filmes-A.txt'])

    def test_series_without_year_preserves_enriched_header(self):
        result,c=self.run_import(series='@A Show\t2020\t123\n1\t1\tdub\t0:1\n',entries=[self.entry('A Show S01E01','series')])
        self.assertIn('@A Show\t2020\t123',result['vod/series-A-0.txt'])
        self.assertIn('0:1,1:2',result['vod/series-A-0.txt'])
        self.assertEqual(c['novas_series'],0)

    def test_year_before_language_marker_does_not_merge_remake(self):
        result,c=self.run_import('A Test (1987)\tdub=0:1\n',entries=[self.entry('A Test (2026) [L]')])
        self.assertIn('A Test (2026)\tleg=1:2',result['vod/filmes-A.txt'])
        self.assertIn('A Test (1987)\tdub=0:1',result['vod/filmes-A.txt'])

    def test_channel_noise_does_not_create_new_identity(self):
        self.assertEqual(clean_live('WARNER FHD H.265 ¹'),'WARNER')
        self.assertEqual(clean_live('CARTOON NETWOORK HD'),'Cartoon Network')
        self.assertEqual(normalized(clean_live('CANAL GOAT 02')),
                         normalized('Canal GOAT (Jogo 2)'))


if __name__=='__main__':unittest.main()
