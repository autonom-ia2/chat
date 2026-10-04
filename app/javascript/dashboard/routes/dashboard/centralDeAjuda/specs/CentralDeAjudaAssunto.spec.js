import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import CentralDeAjudaAssunto from '../pages/CentralDeAjudaAssunto.vue';

const get = vi.fn();
const push = vi.fn();
const levar = vi.fn();
const pedirAoGuia = vi.fn();
const rotasDaConta = ref(new Set());
const vistos = ref(new Set());
const guiaDisponivel = ref(true);
const params = { capitulo: '10' };

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valor) =>
      `${chave}${typeof valor === 'object' ? JSON.stringify(valor) : (valor ?? '')}`,
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params }),
  useRouter: () => ({ push }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentAccountId: 1 } }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () =>
      computed(() => () => ({
        autonomia_guide_available: guiaDisponivel.value,
      })),
  };
});
vi.mock('dashboard/composables/useGuiaPedido', () => ({
  useGuiaPedido: () => ({ pedirAoGuia }),
}));
vi.mock('dashboard/composables/useLevarAteLa', () => ({
  useLevarAteLa: () => ({
    destino: rota => (rotasDaConta.value.has(rota) ? { name: rota } : null),
    levar,
  }),
}));
vi.mock('../composables/useArtigosVistos', () => ({
  useArtigosVistos: () => ({ foiVisto: id => vistos.value.has(id) }),
}));
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: { get: (...args) => get(...args) },
}));

const artigo = (id, extra = {}) => ({
  id,
  ref: id.replace('.', '-'),
  titulo: `Título ${id}`,
  descricao: `Descrição ${id}`,
  rota: null,
  video: false,
  ...extra,
});

const CRM = {
  id: '10',
  titulo: 'CRM, funis e negócios',
  artigos: [
    artigo('10.01', { video: true, poster: '/p/10.01.jpg', duracao: 95 }),
    artigo('10.02', { rota: 'crm_funis' }),
    artigo('10.03', { video: true, poster: '/p/10.03.jpg', duracao: 50 }),
  ],
};
const TRILHA = {
  id: '00',
  titulo: 'Primeiros passos',
  artigos: [
    artigo('00.01', { titulo: 'Passo 1 — Perfil' }),
    artigo('00.04', { titulo: 'Passo 4 — Canal' }),
  ],
};

const montar = async (capitulos = [CRM, TRILHA]) => {
  get.mockResolvedValue({ data: { preparando: false, capitulos } });
  const tela = mount(CentralDeAjudaAssunto, {
    global: {
      stubs: {
        Spinner: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
  return tela;
};

const itens = tela => tela.findAll('ol > li');
const botao = (tela, texto) =>
  tela.findAll('button').find(item => item.text().includes(texto));

describe('CentralDeAjudaAssunto', () => {
  beforeEach(() => {
    get.mockReset();
    push.mockClear();
    levar.mockClear();
    pedirAoGuia.mockClear();
    rotasDaConta.value = new Set();
    vistos.value = new Set();
    guiaDisponivel.value = true;
    params.capitulo = '10';
  });

  it('mostra só o capítulo da rota, na ordem da API, com número', async () => {
    const tela = await montar();

    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.CRM'
    );
    expect(tela.text()).not.toContain('Passo 1');
    const lista = itens(tela);
    expect(lista).toHaveLength(3);
    expect(lista.map(item => item.text().slice(0, 1))).toEqual(['1', '2', '3']);
    expect(lista[1].text()).toContain('Título 10.02');
    expect(lista[1].find('a').attributes('data-to')).toBe(
      JSON.stringify({
        name: 'central_de_ajuda_artigo',
        params: { ref: '10-02' },
      })
    );
  });

  it('mostra os fatos: artigos, vídeos, minutos e vistos', async () => {
    vistos.value = new Set(['10.01']);
    const tela = await montar();
    const texto = tela.text();

    expect(texto).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGOS_NO_CAPITULO3'
    );
    expect(texto).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.VIDEOS2');
    // 95 s + 50 s = 145 s, arredondado para cima: 3 min.
    expect(texto).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.MINUTOS3');
    expect(texto).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VISTOS1');
  });

  it('artigo com vídeo tem miniatura e duração; sem vídeo, não', async () => {
    const tela = await montar();
    const [primeiro, segundo] = itens(tela);

    expect(primeiro.find('img').attributes('src')).toBe('/p/10.01.jpg');
    expect(primeiro.text()).toContain('1:35');
    expect(segundo.find('img').exists()).toBe(false);
  });

  it('vídeo sem miniatura publicada ainda mostra o vídeo e a duração', async () => {
    const tela = await montar([
      {
        ...CRM,
        artigos: [artigo('10.01', { video: true, poster: null, duracao: 95 })],
      },
    ]);
    const [item] = itens(tela);

    expect(item.find('img').exists()).toBe(false);
    expect(item.find('.i-lucide-circle-play').exists()).toBe(true);
    expect(item.text()).toContain('1:35');
  });

  it('Abrir não leva de volta à própria Central', async () => {
    rotasDaConta.value = new Set(['central_de_ajuda']);
    const tela = await montar([
      { ...CRM, artigos: [artigo('10.01', { rota: 'central_de_ajuda' })] },
    ]);

    expect(botao(tela, 'ASSUNTO.ABRIR')).toBeUndefined();
  });

  it('nada visto: o botão principal é Começar e abre o primeiro artigo', async () => {
    const tela = await montar();

    await botao(tela, 'ASSUNTO.COMECAR').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: '10-01' },
    });
  });

  it('com algo visto, Continuar leva ao primeiro ainda não visto', async () => {
    vistos.value = new Set(['10.01', '10.03']);
    const tela = await montar();

    const continuar = botao(tela, 'ASSUNTO.CONTINUAR');
    expect(continuar.text()).toContain('Título 10.02');
    await continuar.trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: '10-02' },
    });
    expect(itens(tela)[0].text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VISTO'
    );
  });

  it('tudo visto: Rever do início volta ao primeiro', async () => {
    vistos.value = new Set(['10.01', '10.02', '10.03']);
    const tela = await montar();

    await botao(tela, 'ASSUNTO.REVER').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: '10-01' },
    });
  });

  it('Abrir o assunto só aparece quando a tela existe para a conta', async () => {
    let tela = await montar();
    expect(botao(tela, 'ASSUNTO.ABRIR')).toBeUndefined();

    rotasDaConta.value = new Set(['crm_funis']);
    tela = await montar();
    await botao(tela, 'ASSUNTO.ABRIR').trigger('click');
    expect(levar).toHaveBeenCalledWith({ rota: 'crm_funis' });
  });

  it('Primeiros passos não numera o círculo (o título já tem "Passo N")', async () => {
    params.capitulo = '00';
    vistos.value = new Set(['00.01']);
    const tela = await montar();
    const [visto, pendente] = itens(tela);

    expect(visto.find('.i-lucide-check').exists()).toBe(true);
    expect(pendente.text().startsWith('Passo 4')).toBe(true);
  });

  it('assunto inexistente ou sem artigo para a conta mostra o vazio', async () => {
    params.capitulo = '99';
    let tela = await montar();
    expect(tela.text()).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VAZIO');
    expect(itens(tela)).toHaveLength(0);

    params.capitulo = '10';
    tela = await montar([{ ...CRM, artigos: [] }]);
    expect(tela.text()).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VAZIO');
  });

  it('Central ainda sendo preparada: avisa em vez de dizer que o assunto não existe', async () => {
    get.mockResolvedValue({ data: { preparando: true, capitulos: [] } });
    const tela = mount(CentralDeAjudaAssunto, {
      global: { stubs: { Spinner: true, RouterLink: true } },
    });
    await flushPromises();

    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.PREPARANDO.TITULO'
    );
    expect(tela.text()).not.toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VAZIO'
    );

    get.mockResolvedValue({ data: { preparando: false, capitulos: [CRM] } });
    await tela.find('button').trigger('click');
    await flushPromises();
    expect(itens(tela)).toHaveLength(3);
  });

  it('erro na leitura oferece tentar de novo', async () => {
    get.mockRejectedValueOnce(new Error('falhou'));
    const tela = mount(CentralDeAjudaAssunto, {
      global: { stubs: { Spinner: true, RouterLink: true } },
    });
    await flushPromises();
    expect(tela.text()).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TEXTO');

    get.mockResolvedValue({ data: { capitulos: [CRM] } });
    await tela.find('button').trigger('click');
    await flushPromises();
    expect(get).toHaveBeenCalledTimes(2);
  });

  it('Perguntar ao Guia abre o painel sem texto, só com o Guia disponível', async () => {
    let tela = await montar();
    await botao(tela, 'ASSUNTO.PERGUNTAR').trigger('click');
    expect(pedirAoGuia).toHaveBeenCalledWith();

    guiaDisponivel.value = false;
    tela = await montar();
    expect(botao(tela, 'ASSUNTO.PERGUNTAR')).toBeUndefined();
  });
});
