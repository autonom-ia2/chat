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

    def test_estresse_aleatorio_cobre_tudo_sem_repetir(self):
        # 300 cenários: contagem de specs, de nós e tempos aleatórios (inclusive zeros, empates e specs sem tempo).
        import random
        gerador = random.Random(959)
        for cenario in range(300):
            pasta = Path(tempfile.mkdtemp())
            total = gerador.randint(1, 400)
            shards = gerador.randint(1, 16)
            specs = sorted({f'spec/d{gerador.randint(0, 9)}/s{i}_spec.rb' for i in range(total)})
            exemplos = []
            for spec in specs:
                if gerador.random() < 0.85:  # parte das specs fica sem tempo (spec nova)
                    for _ in range(gerador.randint(1, 4)):
                        exemplos.append({'id': f'./{spec}[1:{gerador.randint(1, 9)}]',
                                         'run_time': gerador.choice([0.0, 0.01, gerador.uniform(0, 30)])})
            (pasta / 'tempos' / 'r').mkdir(parents=True)
            (pasta / 'tempos' / 'r' / 'rspec_results.json').write_text(json.dumps({'examples': exemplos}))
            (pasta / 'specs.txt').write_text('\n'.join(specs) + '\n')
            saida = pasta / 'plan.json'
            rspec_plan.main(['--shards', str(shards), '--specs', str(pasta / 'specs.txt'),
                             '--tempos', str(pasta / 'tempos'), '--saida', str(saida)])
            plano = json.loads(saida.read_text())
            todos = sum(plano['shards'], [])
            self.assertEqual(sorted(todos), specs, f'cenário {cenario}')
            self.assertEqual(len(todos), len(set(todos)), f'cenário {cenario}')
            self.assertEqual(len(plano['shards']), shards, f'cenário {cenario}')
            if len(specs) >= shards:
                self.assertTrue(all(plano['shards']), f'cenário {cenario}: nó vazio')

    def test_equilibrio_nunca_pior_que_a_maior_spec_mais_a_media(self):
        # Garantia do guloso (LPT): a carga máxima fica abaixo de média + maior peso.
        import random
        gerador = random.Random(7)
        for _ in range(100):
            pesos = {f'spec/s{i}_spec.rb': gerador.uniform(0.1, 60) for i in range(gerador.randint(8, 300))}
            nos, _fonte, carga = rspec_plan.dividir(sorted(pesos), 8, pesos)
            self.assertLessEqual(max(carga), sum(pesos.values()) / 8 + max(pesos.values()) + 1e-9)

    def test_specs_de_tempo_zero_nao_se_empilham_num_no_so(self):
        specs = [f'spec/z{i}_spec.rb' for i in range(20)] + ['spec/lento_spec.rb']
        self.escrever_resultado('r', [{'id': f'./{s}[1:1]', 'run_time': 0.0} for s in specs[:20]]
                                + [{'id': './spec/lento_spec.rb[1:1]', 'run_time': 50.0}])
        plano = self.planejar(specs, 4)
        self.assertTrue(all(plano['shards']))
        self.assertEqual(sorted(sum(plano['shards'], [])), sorted(specs))

    def test_todos_os_tempos_zero_caem_no_round_robin(self):
        self.escrever_resultado('r', [{'id': f'./spec/z{i}_spec.rb[1:1]', 'run_time': 0.0} for i in range(6)])
        plano = self.planejar([f'spec/z{i}_spec.rb' for i in range(6)], 3)
        self.assertEqual(plano['fonte'], 'round-robin')

    def test_shards_invalido_derruba(self):
        with self.assertRaises(SystemExit):
            self.planejar(['spec/a_spec.rb'], 0, com_tempos=False)


if __name__ == '__main__':
    unittest.main()
