import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rspec_plan  # noqa: E402


class RspecPlanTest(unittest.TestCase):
    def setUp(self):
        self.pasta = Path(tempfile.mkdtemp())

    def escrever_specs(self, specs):
        caminho = self.pasta / 'specs.txt'
        caminho.write_text('\n'.join(specs) + '\n')
        return caminho

    def escrever_resultado(self, nome, exemplos):
        destino = self.pasta / 'tempos' / nome
        destino.mkdir(parents=True, exist_ok=True)
        (destino / 'rspec_results.json').write_text(json.dumps({'examples': exemplos}))

    def planejar(self, specs, shards, com_tempos=True):
        saida = self.pasta / 'plan.json'
        args = ['--shards', str(shards), '--specs', str(self.escrever_specs(specs)), '--saida', str(saida)]
        if com_tempos:
            args += ['--tempos', str(self.pasta / 'tempos')]
        rspec_plan.main(args)
        return json.loads(saida.read_text())

    def test_sem_tempos_cai_no_round_robin_de_antes(self):
        specs = [f'spec/a{i}_spec.rb' for i in range(5)]
        plano = self.planejar(specs, 2, com_tempos=False)
        self.assertEqual(plano['fonte'], 'round-robin')
        self.assertEqual(plano['shards'][0], ['spec/a0_spec.rb', 'spec/a2_spec.rb', 'spec/a4_spec.rb'])

    def test_equilibra_pelo_tempo_e_cobre_tudo_uma_vez(self):
        specs = ['spec/lento_spec.rb', 'spec/medio_spec.rb', 'spec/rapido1_spec.rb', 'spec/rapido2_spec.rb']
        self.escrever_resultado('rspec-results-0', [
            {'id': './spec/lento_spec.rb[1:1]', 'run_time': 10.0},
            {'id': './spec/medio_spec.rb[1:1]', 'run_time': 6.0},
            {'id': './spec/rapido1_spec.rb[1:1]', 'run_time': 2.0},
            {'id': './spec/rapido2_spec.rb[1:1]', 'run_time': 2.0},
        ])
        plano = self.planejar(specs, 2)
        self.assertEqual(plano['fonte'], 'tempos')
        self.assertEqual(sorted(sum(plano['shards'], [])), sorted(specs))
        self.assertIn(['spec/lento_spec.rb'], plano['shards'])
        self.assertEqual(sorted(plano['carga_prevista_s']), [10.0, 10.0])

    def test_usa_o_arquivo_que_roda_o_exemplo_e_nao_o_shared_example(self):
        self.escrever_resultado('r', [
            {'id': './spec/models/a_spec.rb[1:2]', 'file_path': './spec/support/compartilhado.rb', 'run_time': 3.0},
        ])
        pesos = rspec_plan.carregar_pesos(self.pasta / 'tempos', ['spec/models/a_spec.rb'])
        self.assertEqual(pesos, {'spec/models/a_spec.rb': 3.0})

    def test_spec_nova_sem_tempo_recebe_a_mediana_e_entra_no_plano(self):
        self.escrever_resultado('r', [
            {'id': './spec/a_spec.rb[1:1]', 'run_time': 1.0},
            {'id': './spec/b_spec.rb[1:1]', 'run_time': 3.0},
        ])
        plano = self.planejar(['spec/a_spec.rb', 'spec/b_spec.rb', 'spec/nova_spec.rb'], 2)
        self.assertIn('spec/nova_spec.rb', sum(plano['shards'], []))

    def test_ignora_spec_apagada_e_json_quebrado(self):
        self.escrever_resultado('r', [{'id': './spec/apagada_spec.rb[1:1]', 'run_time': 99.0}])
        quebrado = self.pasta / 'tempos' / 'x'
        quebrado.mkdir(parents=True)
        (quebrado / 'rspec_results.json').write_text('{nao e json')
        plano = self.planejar(['spec/a_spec.rb', 'spec/b_spec.rb'], 2)
        self.assertEqual(plano['fonte'], 'round-robin')

    def test_e_deterministico(self):
        self.escrever_resultado('r', [{'id': f'./spec/s{i}_spec.rb[1:1]', 'run_time': float(i % 4)} for i in range(30)])
        specs = [f'spec/s{i}_spec.rb' for i in range(30)]
        self.assertEqual(self.planejar(specs, 8), self.planejar(specs, 8))

    def test_lista_vazia_ou_repetida_derruba(self):
        with self.assertRaises(SystemExit):
            self.planejar([], 2)
        with self.assertRaises(SystemExit):
            self.planejar(['spec/a_spec.rb', 'spec/a_spec.rb'], 2)

    def test_verificacao_recusa_plano_que_perde_ou_duplica_spec(self):
        specs = ['spec/a_spec.rb', 'spec/b_spec.rb']
        with self.assertRaises(SystemExit):
            rspec_plan.verificar(specs, [['spec/a_spec.rb'], []], 2)
        with self.assertRaises(SystemExit):
            rspec_plan.verificar(specs, [['spec/a_spec.rb', 'spec/b_spec.rb'], ['spec/b_spec.rb']], 2)


if __name__ == '__main__':
    unittest.main()
