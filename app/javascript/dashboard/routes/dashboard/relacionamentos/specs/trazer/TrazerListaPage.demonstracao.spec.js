import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  botao,
  erroHttp,
  escolher,
  esperarPor,
  irAteConferir,
  marca,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
import { DURACAO_DA_TRAZIDA_MS } from '../../demo/trazer';

// A página "Trazer minha lista" inteira (#2894) em demonstração, da planilha
// de exemplo ao Pronto, com o texto real em pt_BR e relógio falso.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);

// A demonstração leva DURACAO_DA_TRAZIDA_MS para trazer a lista; a folga cobre
// a consulta seguinte ao fim (a espera entre uma e outra chega a 5 s).
const ATE_TRAZER_TUDO_MS = DURACAO_DA_TRAZIDA_MS + 5000;

const QUARENTA_POR_CENTO_MS = DURACAO_DA_TRAZIDA_MS * 0.4;

const estado = vi.hoisted(() => ({ demo: 'cheio' }));

const empurrar = vi.hoisted(() => vi.fn());

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
  useRouter: () => ({ push: empurrar, replace: vi.fn() }),
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

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

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
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(4));
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
    expect(w.get('h1').text()).toBe('Achei 203 pessoas.');
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
    // "Novas" é o número da leitura; quem foi consertado entra na conta do botão.
    expect(w.get('[data-contador="NOVAS"] .sr-only').text()).toBe('180 novas');
    expect(w.get('[data-contador="PRECISAM"] .sr-only').text()).toBe(
      '7 precisam de você'
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
      'Corrija o telefone para salvar.'
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
      'Pode sair desta tela. A lista aparece aqui embaixo quando terminar.'
    );
    // Enquanto traz, o passo 3 é "Trazendo"; vira "Pronto" só no fim.
    expect(marca(w, 'etapas').get('[aria-current="step"]').text()).toContain(
      'Trazendo'
    );
    // A tela pergunta de novo com a espera crescendo (1,5 s, 2,25 s, 3,375 s e
    // daí 5 s), e a barra anda aos poucos, sem salto grande.
    const barra = () =>
      w.get('[role="progressbar"]').attributes('aria-valuenow');
    await vi.advanceTimersByTimeAsync(1500);
    await esperarPor(() => expect(barra()).toBe('8'));
    await vi.advanceTimersByTimeAsync(2250);
    await esperarPor(() => expect(barra()).toBe('22'));
    await vi.advanceTimersByTimeAsync(3375);
    await esperarPor(() => expect(barra()).toBe('41'));
    await vi.advanceTimersByTimeAsync(5000);
    await esperarPor(() => expect(barra()).toBe('71'));
    await vi.advanceTimersByTimeAsync(5000);
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
    await vi.advanceTimersByTimeAsync(ATE_TRAZER_TUDO_MS);
    await aparece(w, 'pronto');
    await botao(w, 'Trazer outra lista').trigger('click');
    await aparece(w, 'enviar');
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(5));
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
    await vi.advanceTimersByTimeAsync(QUARENTA_POR_CENTO_MS);

    const volta = await abrir();
    await esperarPor(() =>
      expect(volta.findAll('[data-lista]')).toHaveLength(5)
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
    await vi.advanceTimersByTimeAsync(ATE_TRAZER_TUDO_MS);
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

// #2896, Fatia 2 — a lista que parou no meio também existe em demonstração.
describe('?demo=cheio: a lista que parou no meio', () => {
  it('diz que não foi trazida, tem "Tentar de novo" e volta a ser trazida até ficar pronta', async () => {
    const w = await abrir();
    await aparece(w, 'tentar-de-novo');
    const falhou = w.get('[data-situacao="falhou"]');
    expect(falhou.text()).toBe('Não consegui trazer esta lista.');
    const id = falhou.element.closest('[data-lista]').dataset.lista;
    const situacao = () => w.get(`[data-lista="${id}"] [data-situacao]`).text();
    await marca(w, 'tentar-de-novo').trigger('click');
    await esperarPor(() => expect(situacao()).toContain('Trazendo'));
    expect(marca(w, 'tentar-de-novo').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(ATE_TRAZER_TUDO_MS);
    await esperarPor(() => expect(situacao()).toBe('Pronto'));
    w.unmount();
  });
});
