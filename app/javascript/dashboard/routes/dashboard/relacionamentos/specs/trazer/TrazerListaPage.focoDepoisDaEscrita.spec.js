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
// (#2896, Fatia 2): para onde vai o foco depois de uma escrita numa linha cujo
// controle é um botão. Enquanto a escrita não volta os botões ficam desligados
// e não recebem foco: o foco espera a escrita acabar.
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

const EMAIL = {
  linha: 37,
  tipo: 'email',
  nome: 'Rita Carvalhedo',
  valor: 'rita.carvalhedo.exemplo.com.br',
  estado: 'aberto',
};
const REPETIDA = {
  linha: 143,
  tipo: 'duplicada',
  nome: 'Paulo Hortêncio',
  valor: 'Paulo Hortêncio',
  outraLinha: 88,
  duplicadas: [
    { linha: 88, telefone: '(11) 94410-0088', email: '' },
    { linha: 143, telefone: '(11) 94410-0143', email: '' },
  ],
  estado: 'aberto',
};
// A fórmula está na empresa: a tela não conserta, só deixa de fora.
const COM_FORMULA = {
  linha: 160,
  tipo: 'formula',
  campo: 'empresa',
  nome: 'Caio Camargo',
  estado: 'aberto',
};
const ENTRAM = 7;

const leitura = (extra = {}) => ({
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Cel', destino: 'telefone' },
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
    entram: ENTRAM,
  },
  exemplos: [
    { nome: 'Ana Albuquerino', telefone: '+5511987650001', email: '' },
  ],
  problemas: [EMAIL, REPETIDA, COM_FORMULA],
  problemas_total: 3,
  pagina: 1,
  por_pagina: 200,
  ...extra,
});

const deixada = problema => ({
  data: { problema: { ...problema, estado: 'deixado' }, entram: ENTRAM },
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
    value: [new File(['nome;cel'], 'Clientes 2025.csv')],
    configurable: true,
  });
  await entrada.trigger('change');
  await aparece(w, 'pergunta');
  await escolher(w, 'sim_todas');
  await continuar(w);
  await aparece(w, 'conferir');
  return w;
};

const focoEm = elemento =>
  esperarPor(() => expect(document.activeElement).toBe(elemento()));

describe('a recusa na linha repetida devolve o foco', () => {
  it.each([
    ['o servidor falha (500)', () => erroHttp(500)],
    ['a rede cai', () => new Error('Network Error')],
  ])(
    '"Ficar com esta" e %s: o alerta aparece, o botão religa e o foco volta a ele',
    async (_, falha) => {
      const w = await ateConferir();
      servidor.consertar.mockRejectedValueOnce(falha());
      const linha = () => w.get('[data-linha="143"]');
      const escolha = () => linha().get('[data-opcao="88"]');
      await escolha().trigger('click');
      await esperarPor(() =>
        expect(linha().find('[role="alert"]').exists()).toBe(true)
      );
      expect(linha().get('[role="alert"]').text()).toBe(
        'Não consegui salvar esta linha. Tente de novo.'
      );
      expect(servidor.consertar).toHaveBeenCalledWith(812, 143, {
        ficar_com: 88,
      });
      await esperarPor(() =>
        expect(escolha().attributes('disabled')).toBeUndefined()
      );
      await focoEm(() => escolha().element);
      w.unmount();
    }
  );
});

describe('resolver uma linha leva o foco à próxima aberta, mesmo quando ela só tem botões', () => {
  it('a próxima é a repetida: o foco vai para a primeira escolha dela', async () => {
    const w = await ateConferir();
    servidor.deixarDeFora.mockResolvedValue(deixada(EMAIL));
    await w
      .get('[data-linha="37"] [data-relacionamentos="deixar-de-fora"]')
      .trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-linha="37"]').text()).toContain('Deixada de fora')
    );
    await focoEm(() => w.get('[data-linha="143"] [data-opcao="88"]').element);
    w.unmount();
  });

  it('a próxima é a linha sem conserto: o foco vai para o "Deixar de fora" dela', async () => {
    const w = await ateConferir();
    servidor.deixarDeFora.mockResolvedValue(deixada(REPETIDA));
    await w
      .get('[data-linha="143"] [data-relacionamentos="deixar-de-fora"]')
      .trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-linha="143"]').text()).toContain('Deixada de fora')
    );
    await focoEm(
      () =>
        w.get('[data-linha="160"] [data-relacionamentos="deixar-de-fora"]')
          .element
    );
    w.unmount();
  });

  it('voltar atrás na repetida: o foco vai para a primeira escolha dela', async () => {
    const w = await ateConferir();
    servidor.deixarDeFora.mockResolvedValue(deixada(REPETIDA));
    servidor.reabrir.mockResolvedValue({
      data: { problema: REPETIDA, entram: ENTRAM },
    });
    await w
      .get('[data-linha="143"] [data-relacionamentos="deixar-de-fora"]')
      .trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-linha="143"]').text()).toContain('Deixada de fora')
    );
    await w
      .get('[data-linha="143"] [data-relacionamentos="voltar-atras"]')
      .trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-linha="143"]').find('form').exists()).toBe(true)
    );
    await focoEm(() => w.get('[data-linha="143"] [data-opcao="88"]').element);
    w.unmount();
  });
});
