import unittest
from scripts.corrigir_catalogo_tvbox import corrigir_linha

class CompatibilidadeTVBoxTest(unittest.TestCase):
    def test_preserva_fontes_ordem_e_metadados_separados(self):
        line = 'Filme (2026)\tdub=0:123,https://novo.example/a.mp4\tleg=2:456.mkv\ttmdb=123\timdb=tt456'
        fixed, meta = corrigir_linha(line)
        self.assertEqual(fixed, line.split('\ttmdb=')[0])
        self.assertEqual(meta, {'tmdb': '123', 'imdb': 'tt456'})

    def test_proxy_relativo_vira_url_original_sem_mudar_demais_fontes(self):
        line = 'Filme\tdub=/api/proxy-video?url=https%3A%2F%2Forigem.example%2Ffilme.mp4,0:987'
        self.assertEqual(corrigir_linha(line)[0], 'Filme\tdub=https://origem.example/filme.mp4,0:987')

    def test_sem_nexus_fica_identico_e_correcao_idempotente(self):
        line = 'Antigo\tdub=0:123,https://reserva.example/a.mp4'
        self.assertEqual(corrigir_linha(line), (line, {}))
        self.assertEqual(corrigir_linha(corrigir_linha(line)[0])[0], line)

if __name__ == '__main__':
    unittest.main()
