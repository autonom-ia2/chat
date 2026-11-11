import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';

// A página "Trazer minha lista" inteira (#2894), da planilha de exemplo ao
// Pronto e ao Desfazer, com o texto real em pt_BR e relógio falso.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);
const estado = vi.hoisted(() => ({ demo: 'cheio' }));
const empurrar = vi.hoisted(() => vi.fn());
const alertar = vi.hoisted(() => vi.fn());

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: empurrar }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alertar }));
vi.mock('../../fonte/modoDemo', () => ({ usarDemo: () => estado.demo }));
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
const aparece = (w, nome) =>
  vi.waitFor(() => expect(marca(w, nome).exists()).toBe(true));
const some = (w, nome) =>
  vi.waitFor(() => expect(marca(w, nome).exists()).toBe(false));

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
  await vi.waitFor(() =>
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
    await vi.waitFor(() => expect(w.findAll('[data-lista]')).toHaveLength(2));
    expect(w.get('a').text()).toContain('Pessoas');
    w.unmount();
  });

  it('fora da demonstração não há link de exemplo, e ler dá o erro com botão', async () => {
    estado.demo = null;
    const w = await abrir();
    expect(marca(w, 'usar-exemplo').exists()).toBe(false);
    await vi.waitFor(() => expect(marca(w, 'erro').exists()).toBe(true));
    expect(marca(w, 'erro').text()).toContain(
      'Não consegui mostrar o que você já trouxe'
    );
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
    expect(w.get('h1').text()).toBe('Essas pessoas já são suas clientes?');
    w.unmount();
  });
});

describe('Perguntas', () => {
  it('Continuar espera a escolha e Voltar leva de volta ao Enviar', async () => {
    const w = await abrir();
    await marca(w, 'usar-exemplo').trigger('click');
    await aparece(w, 'pergunta');
    expect(marca(w, 'continuar').attributes('disabled')).toBeDefined();
    await escolher(w, 'algumas');
    expect(marca(w, 'continuar').attributes('disabled')).toBeDefined();
    expect(w.text()).toContain('Qual coluna diz quem é cliente?');
    await botao(w, 'Voltar').trigger('click');
    await aparece(w, 'enviar');
    w.unmount();
  });

  it('o foco vai para o título de cada tela nova', async () => {
    const w = await abrir();
    await marca(w, 'usar-exemplo').trigger('click');
    await aparece(w, 'pergunta');
    await vi.waitFor(() =>
      expect(document.activeElement).toBe(w.get('h1').element)
    );
    w.unmount();
  });
});

describe('da planilha de exemplo até Pronto', () => {
  it('Conferir mostra a frase, as fichas e o botão; consertar muda os números na hora', async () => {
    const w = await abrir();
    await irAteConferir(w);
    expect(w.get('h1').text()).toBe(
      'Achei 200 pessoas. 180 são novas, 15 já estavam aqui e vão ser completadas, 5 precisam de você.'
    );
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
    expect(w.findAll('[data-ficha-de-exemplo]')).toHaveLength(3);
    expect(
      w.findAll('[data-ficha-de-exemplo] [data-selo="cliente"]')
    ).toHaveLength(3);

    const linha62 = w.get('[data-linha="62"]');
    await linha62.get('input').setValue('Ana Lima');
    await linha62.get('form').trigger('submit');
    await vi.waitFor(() =>
      expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 196 pessoas')
    );
    expect(w.get('h1').text()).toContain('181 são novas');
    expect(w.get('h1').text()).toContain('4 precisam de você');
    expect(w.get('[data-linha="62"]').text()).toContain('Pronto');
    w.unmount();
  });

  it('consertar o telefone no campo de telefone libera o Salvar', async () => {
    const w = await abrir();
    await irAteConferir(w);
    const linha = w.get('[data-linha="14"]');
    const guardar = () =>
      linha.findAll('button').find(b => b.text() === 'Salvar');
    expect(guardar().attributes('disabled')).toBeDefined();
    await linha.get('input').setValue('11973800014');
    expect(guardar().attributes('disabled')).toBeUndefined();
    await linha.get('form').trigger('submit');
    await vi.waitFor(() =>
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
    await vi.waitFor(() =>
      expect(w.get('[data-linha="171"]').text()).toContain('Deixada de fora')
    );
    expect(w.get('h1').text()).toContain('1 ficou de fora');
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
    expect(marca(w, 'etapas').get('[aria-current="step"]').text()).toContain(
      'Pronto'
    );
    await vi.advanceTimersByTimeAsync(3000);
    await vi.waitFor(() =>
      expect(w.get('[role="progressbar"]').attributes('aria-valuenow')).toBe(
        '50'
      )
    );
    await vi.advanceTimersByTimeAsync(3300);
    await aparece(w, 'pronto');
    expect(marca(w, 'pronto').text()).toContain('195 pessoas chegaram.');
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
    await vi.waitFor(() => expect(w.findAll('[data-lista]')).toHaveLength(3));
    expect(w.findAll('[data-lista]')[0].text()).toContain(
      'Planilha de exemplo.xlsx'
    );
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
    await vi.waitFor(() =>
      expect(volta.findAll('[data-lista]')).toHaveLength(3)
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
    await vi.waitFor(() =>
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
    expect(marca(w, 'erro').text()).toContain(
      'Não consegui trazer a lista. Tente de novo.'
    );
    expect(marca(w, 'conferir').exists()).toBe(true);
    w.unmount();
  });
});

describe('Desfazer', () => {
  const abrirDialogoDaLista = async () => {
    const w = await abrir();
    await vi.waitFor(() => expect(w.findAll('[data-lista]')).toHaveLength(2));
    await w
      .get('[data-lista] [data-relacionamentos="desfazer"]')
      .trigger('click');
    await aparece(w, 'dialogo-desfazer');
    return w;
  };

  it('mostra antes o que sai, o que volta e quem já recebeu campanha', async () => {
    const w = await abrirDialogoDaLista();
    await vi.waitFor(() =>
      expect(marca(w, 'dialogo-desfazer').text()).toContain(
        'Isto tira 180 pessoas'
      )
    );
    const texto = marca(w, 'dialogo-desfazer').text();
    expect(texto).toContain('e devolve 15 ao que eram antes.');
    expect(texto).toContain('As conversas que já aconteceram ficam.');
    expect(texto).toContain(
      '3 pessoas já receberam uma campanha. A mensagem enviada não volta.'
    );
    expect(w.get('[data-dialog] h3').text()).toBe('Desfazer esta lista?');
    w.unmount();
  });

  it('Cancelar fecha sem desfazer', async () => {
    const w = await abrirDialogoDaLista();
    await vi.waitFor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await botao(w, 'Cancelar').trigger('click');
    await some(w, 'dialogo-desfazer');
    expect(
      w.findAll('[data-lista] [data-situacao]').map(s => s.text())
    ).toEqual(['Pronto', 'Desfeito']);
    w.unmount();
  });

  it('Desfazer faz a linha virar "Desfeito" e some o botão', async () => {
    const w = await abrirDialogoDaLista();
    await vi.waitFor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await vi.waitFor(() =>
      expect(
        w.findAll('[data-lista] [data-situacao]').map(s => s.text())
      ).toEqual(['Desfeito', 'Desfeito'])
    );
    expect(marca(w, 'desfazer').exists()).toBe(false);
    w.unmount();
  });

  it('erro ao desfazer avisa por toast e o diálogo continua aberto', async () => {
    const w = await abrirDialogoDaLista();
    await vi.waitFor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    // Passado o prazo, a fonte recusa.
    await vi.advanceTimersByTimeAsync(5 * 24 * 60 * 60 * 1000);
    await w.get('[data-dialog]').trigger('submit');
    await vi.waitFor(() =>
      expect(alertar).toHaveBeenCalledWith(
        'Não consegui desfazer. Tente de novo.'
      )
    );
    expect(marca(w, 'dialogo-desfazer').exists()).toBe(true);
    w.unmount();
  });
});
