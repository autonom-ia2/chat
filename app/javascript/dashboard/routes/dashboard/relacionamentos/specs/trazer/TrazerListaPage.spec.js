import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';

// A página "Trazer minha lista" inteira (#2894), da planilha de exemplo ao
// Pronto e ao Desfazer, com o texto real em pt_BR e relógio falso.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);
const estado = vi.hoisted(() => ({ demo: 'cheio' }));
const empurrar = vi.hoisted(() => vi.fn());
const alertar = vi.hoisted(() => vi.fn());
// O servidor de mentira (fora da demonstração a tela fala com ele, #2896).
const servidor = vi.hoisted(() => ({
  enviar: vi.fn(),
  leitura: vi.fn(),
  trocarColuna: vi.fn(),
  listas: vi.fn(),
  andamento: vi.fn(),
  confirmar: vi.fn(),
}));
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: {} },
  });

vi.mock('dashboard/api/relacionamentosTrazer', () => ({ default: servidor }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: empurrar }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alertar }));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => estado.demo,
}));
// A fonte de verdade, sem as esperas da demonstração.
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    trazerFonte: opcoes =>
      original.trazerFonte({
        ...opcoes,
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      }),
  };
});

const DialogFalso = {
  props: ['title'],
  emits: ['close', 'confirm'],
  methods: {
    open() {
      this.aberto = true;
    },
    close() {
      this.aberto = false;
      this.$emit('close');
    },
  },
  data: () => ({ aberto: false }),
  template: `<form v-if="aberto" data-dialog @submit.prevent="$emit('confirm')"><h3>{{ title }}</h3><slot /><slot name="footer" /></form>`,
};

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

// Espera por condição, com folga para máquina carregada (o padrão é 1 s).
const esperarPor = (verificacao, opcoes) =>
  vi.waitFor(verificacao, { timeout: 5000, ...opcoes });
const aparece = (w, nome) =>
  esperarPor(() => expect(marca(w, nome).exists()).toBe(true));
const some = (w, nome) =>
  esperarPor(() => expect(marca(w, nome).exists()).toBe(false));

const abrir = async () => {
  const w = mount(TrazerListaPage, {
    attachTo: document.body,
    global: { stubs: { RouterLink: RouterLinkStub, Dialog: DialogFalso } },
  });
  await flushPromises();
  return w;
};

const escolher = async (w, resposta) => {
  await marca(w, 'pergunta')
    .get(`[data-resposta="${resposta}"]`)
    .trigger('click');
};
const continuar = async w => {
  await marca(w, 'continuar').trigger('click');
};

// Do link de exemplo até a tela Conferir.
const irAteConferir = async w => {
  await marca(w, 'usar-exemplo').trigger('click');
  await aparece(w, 'pergunta');
  await escolher(w, 'sim_todas');
  await continuar(w);
  await esperarPor(() =>
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('telefone')
  );
  await escolher(w, 'da_pessoa');
  await continuar(w);
  await aparece(w, 'conferir');
};

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = 'cheio';
  empurrar.mockClear();
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

describe('Enviar', () => {
  it('mostra título, etapas, área de soltar, link de exemplo e o histórico', async () => {
    const w = await abrir();
    expect(w.attributes('data-relacionamentos')).toBe('trazer');
    expect(w.get('h1').text()).toBe('Traga sua lista. A gente organiza.');
    expect(marca(w, 'etapas').get('[aria-current="step"]').text()).toContain(
      'Enviar'
    );
    expect(marca(w, 'soltar-arquivo').exists()).toBe(true);
    expect(marca(w, 'usar-exemplo').exists()).toBe(true);
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(3));
    expect(w.get('a').text()).toContain('Pessoas');
    w.unmount();
  });

  it('fora da demonstração não há link de exemplo, e o histórico que o servidor não entrega dá o erro com botão', async () => {
    estado.demo = null;
    const w = await abrir();
    expect(marca(w, 'usar-exemplo').exists()).toBe(false);
    await esperarPor(() => expect(marca(w, 'erro').exists()).toBe(true));
    expect(marca(w, 'erro').text()).toContain(
      'Não consegui mostrar o que você já trouxe'
    );
    expect(marca(w, 'sem-acesso').exists()).toBe(false);
    w.unmount();
  });

  it('demo vazio: o histórico é uma frase, sem botão', async () => {
    estado.demo = 'vazio';
    const w = await abrir();
    await aparece(w, 'vazio');
    expect(marca(w, 'vazio').text()).toBe(
      'Você ainda não trouxe nenhuma lista.'
    );
    expect(marca(w, 'historico').find('button').exists()).toBe(false);
    w.unmount();
  });

  it('arquivo que não é planilha mostra a frase e não lê', async () => {
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['x'], 'foto.png')],
      configurable: true,
    });
    await entrada.trigger('change');
    expect(w.text()).toContain(
      'Este arquivo não é uma planilha. Use Excel ou CSV.'
    );
    expect(w.text()).not.toContain('Lendo sua planilha…');
    w.unmount();
  });

  it('planilha boa mostra "Lendo sua planilha…" e depois a primeira pergunta', async () => {
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['x'], 'clientes.xlsx')],
      configurable: true,
    });
    await entrada.trigger('change');
    expect(w.text()).toContain('Lendo sua planilha…');
    await aparece(w, 'pergunta');
    expect(w.get('h1').text()).toBe('Essas pessoas já são clientes?');
    w.unmount();
  });
});

describe('Perguntas', () => {
  it('Continuar espera a escolha e Voltar leva de volta ao Enviar', async () => {
    const w = await abrir();
    await marca(w, 'usar-exemplo').trigger('click');
    await aparece(w, 'pergunta');
    // Continuar nunca nasce desligado: sem resposta, o clique diz o que falta.
    expect(marca(w, 'continuar').attributes('disabled')).toBeUndefined();
    await marca(w, 'continuar').trigger('click');
    expect(marca(w, 'pergunta').exists()).toBe(true);
    expect(w.get('[role="alert"]').text()).toBe('Escolha uma das respostas.');
    await escolher(w, 'algumas');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    expect(w.text()).toContain('Qual coluna diz quem é cliente?');
    await marca(w, 'continuar').trigger('click');
    expect(w.get('[role="alert"]').text()).toBe('Escolha a coluna.');
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('clientes');
    await botao(w, 'Voltar').trigger('click');
    await aparece(w, 'enviar');
    w.unmount();
  });

  it('o foco vai para o título de cada tela nova', async () => {
    const w = await abrir();
    await marca(w, 'usar-exemplo').trigger('click');
    await aparece(w, 'pergunta');
    await esperarPor(() =>
      expect(document.activeElement).toBe(w.get('h1').element)
    );
    w.unmount();
  });
});

describe('da planilha de exemplo até Pronto', () => {
  it('Conferir mostra a frase, as fichas e o botão; consertar muda os números na hora', async () => {
    const w = await abrir();
    await irAteConferir(w);
    expect(w.get('h1').text()).toBe('Achei 200 pessoas.');
    expect(w.get('[data-contador="NOVAS"] .sr-only').text()).toBe('180 novas');
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
    expect(w.findAll('[data-ficha-de-exemplo]')).toHaveLength(3);
    expect(
      w.findAll('[data-ficha-de-exemplo] [data-selo="cliente"]')
    ).toHaveLength(3);

    const linha62 = w.get('[data-linha="62"]');
    await linha62.get('input').setValue('Ana Brandolim');
    await linha62.get('form').trigger('submit');
    await esperarPor(() =>
      expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 196 pessoas')
    );
    expect(w.get('[data-contador="NOVAS"] .sr-only').text()).toBe('181 novas');
    expect(w.get('[data-contador="PRECISAM"] .sr-only').text()).toBe(
      '4 precisam de você'
    );
    expect(w.get('[data-linha="62"]').text()).toContain('Pronto');
    w.unmount();
  });

  it('consertar o telefone no campo de telefone permite salvar; sem consertar, o clique diz o que falta', async () => {
    const w = await abrir();
    await irAteConferir(w);
    const linha = w.get('[data-linha="14"]');
    const guardar = () =>
      linha.findAll('button').find(b => b.text() === 'Salvar');
    expect(guardar().attributes('disabled')).toBeUndefined();
    await linha.get('form').trigger('submit');
    expect(linha.get('[role="alert"]').text()).toBe(
      'Escreva o telefone para salvar.'
    );
    expect(document.activeElement).toBe(linha.get('input').element);
    await linha.get('input').setValue('11973800014');
    expect(linha.find('[role="alert"]').exists()).toBe(false);
    await linha.get('form').trigger('submit');
    await esperarPor(() =>
      expect(w.get('[data-linha="14"]').text()).toContain('Pronto')
    );
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 196 pessoas');
    w.unmount();
  });

  it('Deixar de fora tira a linha dos que precisam de você', async () => {
    const w = await abrir();
    await irAteConferir(w);
    await w
      .get('[data-linha="171"]')
      .get('[data-relacionamentos="deixar-de-fora"]')
      .trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-linha="171"]').text()).toContain('Deixada de fora')
    );
    expect(w.get('[data-contador="DEIXADAS"] .sr-only').text()).toBe(
      '1 ficou de fora'
    );
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
    w.unmount();
  });

  it('trazer mostra o andamento e termina em "N pessoas chegaram."', async () => {
    const w = await abrir();
    await irAteConferir(w);
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'andamento');
    expect(w.get('[role="progressbar"]').attributes('aria-valuenow')).toBe('0');
    expect(w.text()).toContain(
      'Pode fechar esta tela; eu aviso quando terminar.'
    );
    // Enquanto traz, o passo 3 é "Trazendo"; vira "Pronto" só no fim.
    expect(marca(w, 'etapas').get('[aria-current="step"]').text()).toContain(
      'Trazendo'
    );
    await vi.advanceTimersByTimeAsync(3000);
    await esperarPor(() =>
      expect(w.get('[role="progressbar"]').attributes('aria-valuenow')).toBe(
        '50'
      )
    );
    await vi.advanceTimersByTimeAsync(3300);
    await aparece(w, 'pronto');
    expect(marca(w, 'pronto').text()).toContain(
      '180 pessoas chegaram e 15 foram completadas.'
    );
    // S2: o histórico aparece abaixo, com a lista recém-trazida no topo.
    await esperarPor(() =>
      expect(w.findAll('[data-lista]').length).toBeGreaterThan(3)
    );
    const [primeira] = w.findAll('[data-lista]');
    expect(primeira.text()).toContain('Clientes 2025.xlsx');
    expect(primeira.text()).toContain('195 pessoas');
    expect(primeira.find('[data-relacionamentos="desfazer"]').exists()).toBe(
      true
    );
    await marca(w, 'ver-as-pessoas').trigger('click');
    expect(empurrar).toHaveBeenCalledWith({ name: 'relationships_home' });
    w.unmount();
  });

  it('"Trazer outra lista" volta ao Enviar e a lista nova está no histórico', async () => {
    const w = await abrir();
    await irAteConferir(w);
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'andamento');
    await vi.advanceTimersByTimeAsync(6500);
    await aparece(w, 'pronto');
    await botao(w, 'Trazer outra lista').trigger('click');
    await aparece(w, 'enviar');
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(4));
    expect(w.findAll('[data-lista]')[0].text()).toContain('Clientes 2025.xlsx');
    expect(w.findAll('[data-lista]')[0].get('[data-situacao]').text()).toBe(
      'Pronto'
    );
    w.unmount();
  });

  it('se a pessoa sai e volta, o histórico mostra "Trazendo 40%"', async () => {
    const w = await abrir();
    await irAteConferir(w);
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'andamento');
    w.unmount();
    await vi.advanceTimersByTimeAsync(2400);

    const volta = await abrir();
    await esperarPor(() =>
      expect(volta.findAll('[data-lista]')).toHaveLength(4)
    );
    // O relógio anda um pouco enquanto a tela monta: 40% ou 41%.
    const situacao = volta
      .findAll('[data-lista]')[0]
      .get('[data-situacao]')
      .text();
    expect(situacao.startsWith('Trazendo 4')).toBe(true);
    expect(
      volta
        .findAll('[data-lista]')[0]
        .find('[data-relacionamentos="desfazer"]')
        .exists()
    ).toBe(false);
    await vi.advanceTimersByTimeAsync(4000);
    await esperarPor(() =>
      expect(
        volta.findAll('[data-lista]')[0].get('[data-situacao]').text()
      ).toBe('Pronto')
    );
    volta.unmount();
  });

  it('erro ao trazer fica na tela Conferir com o botão de tentar de novo', async () => {
    const w = await abrir();
    await irAteConferir(w);
    // Uma leitura que a fonte não conhece faz o trazer falhar.
    esquecerMemoriaDaDemo();
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'erro');
    expect(marca(w, 'erro').text()).toContain('Não consegui trazer a lista.');
    expect(marca(w, 'conferir').exists()).toBe(true);
    w.unmount();
  });
});

describe('?demo=vazio', () => {
  it('a tela Enviar mostra o histórico vazio, sem lista nenhuma', async () => {
    estado.demo = 'vazio';
    const w = await abrir();
    await aparece(w, 'vazio');
    expect(marca(w, 'vazio').text()).toBe(
      'Você ainda não trouxe nenhuma lista.'
    );
    expect(w.findAll('[data-lista]')).toHaveLength(0);
    w.unmount();
  });
});

describe('Desfazer a lista recém-trazida, ali mesmo no Pronto', () => {
  it('abre o mesmo diálogo, com a prévia da planilha de exemplo', async () => {
    const w = await abrir();
    await irAteConferir(w);
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'andamento');
    await vi.advanceTimersByTimeAsync(6500);
    await aparece(w, 'pronto');
    await esperarPor(() =>
      expect(w.findAll('[data-lista]').length).toBeGreaterThan(3)
    );
    await w
      .get('[data-lista]:first-child [data-relacionamentos="desfazer"]')
      .trigger('click');
    await aparece(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(marca(w, 'dialogo-desfazer').text()).toContain(
        'Isto tira as 162 pessoas'
      )
    );
    expect(marca(w, 'dialogo-desfazer').text()).toContain(
      '18 ficam aqui, porque já conversaram com você ou já receberam campanha.'
    );
    w.unmount();
  });
});

describe('Desfazer', () => {
  const abrirDialogoDaLista = async () => {
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(3));
    await w
      .get('[data-lista] [data-relacionamentos="desfazer"]')
      .trigger('click');
    await aparece(w, 'dialogo-desfazer');
    return w;
  };

  it('mostra antes o que sai, quem fica aqui e o que volta', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(marca(w, 'dialogo-desfazer').text()).toContain(
        'Isto tira as 104 pessoas'
      )
    );
    const texto = marca(w, 'dialogo-desfazer').text();
    expect(texto).toContain(
      'As 12 que já estavam aqui voltam a ser como eram.'
    );
    expect(texto).toContain(
      '16 ficam aqui, porque já conversaram com você ou já receberam campanha.'
    );
    expect(texto).not.toContain('As conversas que já aconteceram ficam.');
    expect(
      w.get('[data-dialog] [data-relacionamentos="titulo-do-dialogo"]').text()
    ).toBe('Desfazer “Clientes de setembro.xlsx”?');
    w.unmount();
  });

  it('Cancelar fecha sem desfazer', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await botao(w, 'Cancelar').trigger('click');
    await some(w, 'dialogo-desfazer');
    expect(
      w.findAll('[data-lista] [data-situacao]').map(s => s.text())
    ).toEqual(['Pronto', 'Desfeito', 'Pronto']);
    w.unmount();
  });

  it('Desfazer faz a linha virar "Desfeito" e some o botão', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(
        w.findAll('[data-lista] [data-situacao]').map(s => s.text())
      ).toEqual(['Desfeito', 'Desfeito', 'Pronto'])
    );
    expect(
      w
        .find(
          '[data-lista="trazida-antiga-1"] [data-relacionamentos="desfazer"]'
        )
        .exists()
    ).toBe(false);
    w.unmount();
  });

  it('erro ao desfazer avisa por toast e o diálogo continua aberto', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    // Outra aba já desfez esta lista: a fonte recusa.
    const outraAba = trazerFonte({ demo: 'cheio' }).desfazer(
      'trazida-antiga-1'
    );
    await vi.advanceTimersByTimeAsync(0);
    await outraAba;
    await w.get('[data-dialog]').trigger('submit');
    await esperarPor(() =>
      expect(alertar).toHaveBeenCalledWith(
        'Não consegui desfazer. Tente de novo.'
      )
    );
    expect(marca(w, 'dialogo-desfazer').exists()).toBe(true);
    w.unmount();
  });
});

// #2896 — fora da demonstração a tela fala com o servidor.
describe('com o servidor', () => {
  const SEM_ACESSO =
    'Você não pode trazer listas nesta conta. Peça a quem administra a conta.';
  const doServidor = (id, situacao, extra = {}) => ({
    id,
    arquivo: `lista-${id}.xlsx`,
    quando: '2026-11-08T14:03:00Z',
    quem: 'Marina Pavanelli',
    total: 195,
    situacao,
    porcentagem: 100,
    pode_tentar: false,
    ...extra,
  });

  beforeEach(() => {
    estado.demo = null;
  });

  it.each([401, 403])(
    'recusa %s: só a frase de sem acesso, com role="alert" e sem "Tentar de novo"',
    async status => {
      servidor.listas.mockRejectedValue(erroHttp(status));
      const w = await abrir();
      await aparece(w, 'sem-acesso');
      expect(marca(w, 'sem-acesso').text()).toBe(SEM_ACESSO);
      expect(marca(w, 'sem-acesso').attributes('role')).toBe('alert');
      expect(marca(w, 'erro').exists()).toBe(false);
      expect(marca(w, 'soltar-arquivo').exists()).toBe(false);
      expect(marca(w, 'historico').exists()).toBe(false);
      expect(botao(w, 'Tentar de novo')).toBeUndefined();
      w.unmount();
    }
  );

  it('mostra as listas que o servidor devolve, com o dia e a situação', async () => {
    servidor.listas.mockResolvedValue({
      data: [doServidor(812, 'pronto'), doServidor(700, 'desfazendo')],
    });
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(2));
    const [primeira, segunda] = w.findAll('[data-lista]');
    expect(primeira.text()).toContain('lista-812.xlsx');
    expect(primeira.text()).toContain('em 08/11');
    expect(primeira.get('[data-situacao]').text()).toBe('Pronto');
    expect(segunda.get('[data-situacao]').text()).toBe('Desfeito');
    w.unmount();
  });

  it('lista que falhou: "Tentar de novo" confirma no servidor e a lista volta a ser trazida', async () => {
    servidor.listas
      .mockResolvedValueOnce({
        data: [doServidor(812, 'falhou', { pode_tentar: true })],
      })
      .mockResolvedValue({
        data: [doServidor(812, 'trazendo', { porcentagem: 40 })],
      });
    servidor.confirmar.mockResolvedValue({ data: { id: 812 } });
    const w = await abrir();
    await aparece(w, 'tentar-de-novo');
    expect(w.get('[data-situacao="falhou"]').text()).toBe(
      'Não consegui trazer esta lista.'
    );
    await marca(w, 'tentar-de-novo').trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-lista] [data-situacao]').text()).toBe('Trazendo 40%')
    );
    expect(servidor.confirmar).toHaveBeenCalledWith(812);
    expect(marca(w, 'tentar-de-novo').exists()).toBe(false);
    w.unmount();
  });

  it('da planilha ao Pronto sem perguntas: Enviar → Conferir → Trazer → Pronto', async () => {
    servidor.listas.mockResolvedValue({ data: [] });
    servidor.enviar.mockResolvedValue({ data: { id: 812, situacao: 'lendo' } });
    servidor.leitura.mockResolvedValue({
      data: {
        id: 812,
        situacao: 'pronta',
        arquivo: 'Clientes 2025.csv',
        valores: 'inteiros',
        colunas: [
          { indice: 0, nome: 'Nome', destino: 'nome' },
          { indice: 1, nome: 'Celular', destino: 'telefone' },
        ],
        perguntas: [],
        respostas: {},
        resumo: { total: 2, novas: 1, completadas: 1, comProblema: 0 },
        exemplos: [
          { nome: 'Ana Albuquerino', telefone: '+5511987650001', email: '' },
        ],
        problemas: [],
        problemas_total: 0,
        pagina: 1,
        por_pagina: 200,
      },
    });
    servidor.confirmar.mockResolvedValue({ data: { id: 812 } });
    servidor.andamento.mockResolvedValue({
      data: {
        porcentagem: 100,
        situacao: 'pronto',
        total: 2,
        novas: 1,
        completadas: 1,
      },
    });
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['nome;celular'], 'Clientes 2025.csv')],
      configurable: true,
    });
    await entrada.trigger('change');
    await aparece(w, 'conferir');
    expect(marca(w, 'pergunta').exists()).toBe(false);
    expect(marca(w, 'conferir').text()).toContain('+55 11 98765-0001');
    await botao(w, 'Trazer 2 pessoas').trigger('click');
    await aparece(w, 'pronto');
    expect(servidor.confirmar).toHaveBeenCalledWith(812);
    expect(servidor.andamento).toHaveBeenCalledWith(812);
    expect(marca(w, 'pronto').text()).toContain('1 pessoa chegou');
    w.unmount();
  });

  it('.xls não é enviado: a tela diz a frase do tipo, que não promete .xls', async () => {
    servidor.listas.mockResolvedValue({ data: [] });
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['x'], 'clientes.xls')],
      configurable: true,
    });
    await entrada.trigger('change');
    const frase = marca(w, 'erro-da-planilha').text();
    expect(frase).toBe('Este arquivo não é uma planilha. Use Excel ou CSV.');
    expect(frase).not.toContain('xls');
    expect(servidor.enviar).not.toHaveBeenCalled();
    w.unmount();
  });
});
