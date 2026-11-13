import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  continuar,
  erroHttp,
  escolher,
  esperarPor,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';

// A página "Trazer minha lista" inteira falando com o servidor de mentira
// (#2896, Fatia 2): quando salvar uma linha falha sem o servidor recusar o
// valor (ele caiu, ou a rede caiu), a linha não culpa o que a pessoa escreveu.
// Diz que não conseguiu salvar, no alerta da própria linha e só nele. Só a
// recusa do valor (422 `valor_invalido`) fala do telefone, do e-mail ou do nome.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);

const estado = vi.hoisted(() => ({ demo: null }));

const alertar = vi.hoisted(() => vi.fn());

// O servidor de mentira (fora da demonstração a tela fala com ele, #2896).
const servidor = vi.hoisted(() => ({
  enviar: vi.fn(),
  leitura: vi.fn(),
  responder: vi.fn(),
  consertar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarColuna: vi.fn(),
  trazer: vi.fn(),
  listas: vi.fn(),
  andamento: vi.fn(),
  confirmar: vi.fn(),
}));

// #2897 — a conta destes testes não tem a carteira de seguros: a tela é a das
// listas, sem a pergunta dos seguros.
vi.mock('../../carteira/useContaDeSeguros', async () => {
  const { ref } = await import('vue');
  return { useContaDeSeguros: () => ref(false) };
});

vi.mock('dashboard/api/relacionamentosTrazer', () => ({ default: servidor }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: alertar }));

vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => estado.demo,
}));

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

const NAO_SALVOU = 'Não consegui salvar esta linha. Tente de novo.';

const TELEFONE = {
  linha: 14,
  tipo: 'telefone',
  nome: 'Tadeu Imbirussu',
  valor: '(11) 9738-0014',
  estado: 'aberto',
};
const EMAIL = {
  linha: 37,
  tipo: 'email',
  nome: 'Rita Carvalhedo',
  valor: 'rita.carvalhedo.exemplo.com.br',
  estado: 'aberto',
};
const SEM_NOME = {
  linha: 62,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11954120062',
  estado: 'aberto',
};

const leitura = (extra = {}) => ({
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Cel', destino: 'telefone' },
    { indice: 2, nome: 'E-mail', destino: 'email' },
  ],
  tem_empresa: false,
  perguntas: [{ id: 'clientes' }],
  respostas: {},
  resumo: {
    total: 10,
    novas: 5,
    completadas: 2,
    comProblema: 3,
    juntadas: 0,
    entram: 7,
  },
  exemplos: [
    { nome: 'Ana Albuquerino', telefone: '+5511987650001', email: '' },
  ],
  problemas: [TELEFONE, EMAIL, SEM_NOME],
  problemas_total: 3,
  pagina: 1,
  por_pagina: 200,
  ...extra,
});

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = null;
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Element.prototype.scrollIntoView = vi.fn();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockResolvedValue({ data: [] });
  servidor.enviar.mockResolvedValue({ data: { id: 812, situacao: 'lendo' } });
  servidor.leitura.mockResolvedValue({ data: leitura() });
  servidor.responder.mockResolvedValue({
    data: leitura({ respostas: { clientes: 'sim_todas' } }),
  });
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

const ateConferir = async () => {
  const w = await abrir();
  const entrada = w.get('input[type="file"]');
  Object.defineProperty(entrada.element, 'files', {
    value: [new File(['nome;cel;email'], 'Clientes 2025.csv')],
    configurable: true,
  });
  await entrada.trigger('change');
  await aparece(w, 'pergunta');
  await escolher(w, 'sim_todas');
  await continuar(w);
  await aparece(w, 'conferir');
  return w;
};

// Escreve o valor no campo da linha e salva; devolve quem acha a linha.
const salvarNaLinha = async (w, numero, valor) => {
  const linha = () => w.get(`[data-linha="${numero}"]`);
  await linha().get('input').setValue(valor);
  await linha().get('form').trigger('submit');
  await esperarPor(() =>
    expect(linha().find('[role="alert"]').exists()).toBe(true)
  );
  return linha;
};

const CAMPOS = [
  ['telefone', 14, '11973800014'],
  ['e-mail', 37, 'rita.carvalhedo@exemplo.com.br'],
  ['nome', 62, 'Ana Imbirussu'],
];
const FALHAS = [
  ['o servidor falha (500)', () => erroHttp(500)],
  ['a rede cai', () => new Error('Network Error')],
];
const CASOS = CAMPOS.flatMap(([campo, numero, valor]) =>
  FALHAS.map(([quando, falha]) => [campo, quando, numero, valor, falha])
);

describe('salvar a linha falha sem o servidor recusar o valor', () => {
  it.each(CASOS)(
    'no %s, quando %s: a linha diz que não conseguiu salvar, sem culpar o valor e sem aviso solto',
    async (_campo, _quando, numero, valor, falha) => {
      const w = await ateConferir();
      servidor.consertar.mockRejectedValueOnce(falha());
      const linha = await salvarNaLinha(w, numero, valor);
      expect(linha().findAll('[role="alert"]')).toHaveLength(1);
      expect(linha().get('[role="alert"]').text()).toBe(NAO_SALVOU);
      expect(linha().text()).not.toContain('Confira este');
      await esperarPor(() =>
        expect(document.activeElement).toBe(linha().get('input').element)
      );
      // O alerta da linha já diz tudo: o aviso solto repetiria a mesma frase.
      expect(alertar).not.toHaveBeenCalled();
      // O que a pessoa escreveu continua no campo, para tentar de novo.
      expect(linha().find('form').exists()).toBe(true);
      expect(w.findAll('[role="alert"]')).toHaveLength(1);
      w.unmount();
    }
  );
});

describe('o servidor recusa o valor (422): a frase continua sendo a do valor', () => {
  it.each([
    [
      'telefone',
      'invalid_brazilian_mobile_number',
      14,
      '11973800014',
      'Este telefone não parece um celular do Brasil. Confira o DDD e os dígitos.',
    ],
    [
      'e-mail',
      'invalid_email',
      37,
      'rita@exemplo',
      'Este e-mail não parece certo.',
    ],
    [
      'nome',
      'formula_detected',
      62,
      '=SOMA(A1)',
      'Este texto começa com um sinal (=, +, - ou @). Escreva sem o sinal.',
    ],
    // Motivo que a tela não conhece: ainda é o valor que não vale.
    [
      'telefone',
      'motivo_novo',
      14,
      '11973800014',
      'Confira este telefone e tente de novo.',
    ],
  ])(
    'no %s, com o motivo `%s`',
    async (_campo, motivo, numero, valor, frase) => {
      const w = await ateConferir();
      servidor.consertar.mockRejectedValueOnce(
        erroHttp(422, { error: 'valor_invalido', motivo })
      );
      const linha = await salvarNaLinha(w, numero, valor);
      expect(linha().get('[role="alert"]').text()).toBe(frase);
      expect(alertar).not.toHaveBeenCalled();
      w.unmount();
    }
  );
});
