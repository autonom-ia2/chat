import { h } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideRevisao from '../GuideRevisao.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) => (valores ? `${key}:${JSON.stringify(valores)}` : key),
  }),
  // A frase de conclusão: a chave e, em seguida, cada nome do slot em negrito.
  I18nT: {
    props: ['keypath', 'tag', 'scope'],
    setup(props, { slots }) {
      return () =>
        h('p', { 'data-conclusao': '' }, [
          props.keypath,
          ...Object.values(slots).flatMap(slot => slot()),
        ]);
    },
  },
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { revisao: vi.fn(), continuarRevisao: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 7 }),
}));

// #3158 (B8b) — o cartão da revisão de conversas: andamento, desfecho e os
// motivos agrupados.
const revisao = (extra = {}) => ({
  id: 3,
  status: 'rodando',
  titulo: 'Revisão das notas 1 e 2',
  de: '2026-11-17',
  ate: '2026-11-23',
  total: 214,
  limite: 214,
  lidas: 120,
  falhas: 0,
  faltam: 94,
  motivo: null,
  categorias: [],
  ...extra,
});

const categorias = [
  {
    nome: 'Demora na resposta',
    conversas: [
      { numero: 11, motivo: 'Esperou dois dias' },
      { numero: 12, motivo: 'Ninguém respondeu' },
    ],
  },
  {
    nome: 'Cobrança errada',
    conversas: [{ numero: 13, motivo: 'Veio a mais' }],
  },
  { nome: 'Entrega atrasada', conversas: [{ numero: 14, motivo: 'Atrasou' }] },
  { nome: null, outros: true, conversas: [{ numero: 15, motivo: 'Outro' }] },
];

const montar = () =>
  mount(GuideRevisao, {
    props: { revisaoId: 3 },
    global: {
      stubs: {
        Spinner: { template: '<span data-spinner />' },
        RouterLink: {
          props: ['to'],
          template: '<a :href="to"><slot /></a>',
        },
        Button: {
          props: ['label', 'isLoading'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('GuideRevisao', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it('mostra o andamento e volta a buscar enquanto lê', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValue({ data: revisao() });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.LENDO:{"lidas":120,"limite":214}'
    );
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.REVISAO.PODE_FECHAR');
    expect(
      wrapper.find('[role="progressbar"]').attributes('aria-valuenow')
    ).toBe('56');
    expect(wrapper.text()).not.toContain('MOTIVOS.TITULO');

    vi.advanceTimersByTime(3000);
    await flushPromises();
    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(2);
  });

  it('no fim mostra a conclusão, os motivos e para de buscar', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValue({
      data: revisao({
        status: 'concluida',
        lidas: 214,
        faltam: 0,
        categorias,
      }),
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.DESFECHO.CONCLUIDA'
    );
    const conclusao = wrapper.find('[data-conclusao]');
    expect(conclusao.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.CONCLUSAO_TRES'
    );
    expect(conclusao.findAll('strong').map(item => item.text())).toEqual([
      'Demora na resposta',
      'Cobrança errada',
      'Entrega atrasada',
    ]);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.OUTROS');
    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.MOTIVOS.COMPLETA:{"lidas":214}'
    );

    vi.advanceTimersByTime(3000);
    await flushPromises();
    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(1);
  });

  it('abre as conversas de um motivo, com o link de cada uma', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValue({
      data: revisao({ status: 'concluida', lidas: 214, faltam: 0, categorias }),
    });
    const wrapper = montar();
    await flushPromises();

    const motivo = wrapper.find('button[aria-expanded="false"]');
    await motivo.trigger('click');

    expect(motivo.attributes('aria-expanded')).toBe('true');
    const links = wrapper.findAll('a');
    expect(links.map(link => link.attributes('href'))).toEqual([
      '/app/accounts/7/conversations/11',
      '/app/accounts/7/conversations/12',
    ]);
    expect(wrapper.text()).toContain('Esperou dois dias');
  });

  it('acima de 300, oferece ler as que faltam e volta a acompanhar', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValue({
      data: revisao({
        status: 'concluida',
        total: 386,
        limite: 300,
        lidas: 300,
        faltam: 86,
        categorias,
      }),
    });
    AutonomiaGuideAPI.continuarRevisao.mockResolvedValue({
      data: revisao({ status: 'na_fila', total: 386, limite: 386, lidas: 300 }),
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.DESFECHO.NO_MAXIMO:{"lidas":300,"lidos":300,"limite":300,"total":386}'
    );
    expect(wrapper.find('[data-conclusao]').exists()).toBe(false);
    const ler = wrapper
      .findAll('button')
      .find(item => item.text().includes('LER_FALTAM'));
    expect(ler.text()).toContain('{"faltam":86}');

    await ler.trigger('click');
    await flushPromises();
    expect(AutonomiaGuideAPI.continuarRevisao).toHaveBeenCalledWith(3);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.REVISAO.LENDO');
  });

  it('parada e falha sem chave dizem o desfecho', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValueOnce({
      data: revisao({ status: 'parada', categorias }),
    });
    const parada = montar();
    await flushPromises();
    expect(parada.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.DESFECHO.PARADA:{"lidas":120,"lidos":120,"limite":214,"total":214}'
    );
    expect(parada.find('[data-conclusao]').exists()).toBe(false);
    // Quem pediu para parar não vê convite a continuar (mockup c2).
    expect(parada.text()).toContain('AUTONOMIA_GUIDE.REVISAO.PARADA_FRASE');
    expect(parada.text()).not.toContain('LER_FALTAM');

    AutonomiaGuideAPI.revisao.mockResolvedValueOnce({
      data: revisao({ status: 'falhou', motivo: 'sem_chave', lidas: 0 }),
    });
    const semChave = montar();
    await flushPromises();
    expect(semChave.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.DESFECHO.SEM_CHAVE'
    );
    expect(semChave.text()).not.toContain('LER_FALTAM');
  });

  it('com conversas que não abriram, diz o que mais pesou e quantas ficaram de fora', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValue({
      data: revisao({
        status: 'concluida',
        lidas: 210,
        falhas: 4,
        faltam: 0,
        categorias,
      }),
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-conclusao]').text()).toContain('CONCLUSAO_TRES');
    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.REVISAO.CONCLUSAO_PARCIAL:{"falhas":4}'
    );
  });

  it('abre as conversas de um motivo aos poucos e fecha a lista', async () => {
    const muitas = Array.from({ length: 25 }, (_, k) => ({
      numero: 100 + k,
      motivo: `m${k}`,
    }));
    AutonomiaGuideAPI.revisao.mockResolvedValue({
      data: revisao({
        status: 'concluida',
        lidas: 214,
        faltam: 0,
        categorias: [{ nome: 'Demora', conversas: muitas }],
      }),
    });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('button[aria-expanded="false"]').trigger('click');
    expect(wrapper.findAll('a')).toHaveLength(10);
    const verMais = wrapper
      .findAll('button')
      .find(item => item.text().includes('VER_MAIS'));
    expect(verMais.text()).toContain('{"quantas":15}');

    await verMais.trigger('click');
    expect(wrapper.findAll('a')).toHaveLength(25);
    expect(wrapper.text()).not.toContain('VER_MAIS');

    await wrapper
      .findAll('button')
      .find(item => item.text().includes('MOTIVOS.FECHAR'))
      .trigger('click');
    expect(wrapper.findAll('a')).toHaveLength(0);
  });

  it('para de buscar quando a revisão não existe mais (4xx)', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValueOnce({ data: revisao() });
    AutonomiaGuideAPI.revisao.mockRejectedValueOnce({
      response: { status: 404 },
    });
    const wrapper = montar();
    await flushPromises();

    vi.advanceTimersByTime(3000);
    await flushPromises();
    vi.advanceTimersByTime(60000);
    await flushPromises();

    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.REVISAO.NAO_CARREGOU');
    expect(wrapper.text()).not.toContain('AUTONOMIA_GUIDE.REVISAO.LENDO');
  });

  it('com "espere um pouco" (429), segue buscando', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValueOnce({ data: revisao() });
    AutonomiaGuideAPI.revisao.mockRejectedValueOnce({
      response: { status: 429 },
    });
    AutonomiaGuideAPI.revisao.mockResolvedValue({ data: revisao() });
    const wrapper = montar();
    await flushPromises();

    vi.advanceTimersByTime(3000);
    await flushPromises();
    vi.advanceTimersByTime(6000);
    await flushPromises();

    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(3);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.REVISAO.LENDO');
  });

  it('tentar de novo busca uma vez só, sem a espera do erro anterior', async () => {
    AutonomiaGuideAPI.revisao.mockRejectedValueOnce({
      response: { status: 500 },
    });
    AutonomiaGuideAPI.revisao.mockResolvedValue({
      data: revisao({ status: 'concluida', lidas: 214, faltam: 0 }),
    });
    const wrapper = montar();
    await flushPromises();

    const tentar = wrapper
      .findAll('button')
      .find(item => item.text().includes('TENTAR_DE_NOVO'));
    await tentar.trigger('click');
    await flushPromises();
    vi.advanceTimersByTime(60000);
    await flushPromises();

    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('DESFECHO.CONCLUIDA');
  });

  it('com erro do servidor, tenta de novo cada vez mais devagar', async () => {
    AutonomiaGuideAPI.revisao.mockResolvedValueOnce({ data: revisao() });
    AutonomiaGuideAPI.revisao.mockRejectedValue({ response: { status: 500 } });
    montar();
    await flushPromises();

    vi.advanceTimersByTime(3000);
    await flushPromises();
    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(2);

    vi.advanceTimersByTime(3000);
    await flushPromises();
    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(2);

    vi.advanceTimersByTime(3000);
    await flushPromises();
    expect(AutonomiaGuideAPI.revisao).toHaveBeenCalledTimes(3);
  });

  it('tem os textos em inglês e em português', () => {
    ['CABECALHO', 'LENDO', 'PODE_FECHAR', 'LER_FALTAM'].forEach(chave => {
      expect(en.AUTONOMIA_GUIDE.REVISAO[chave]).toBeTruthy();
      expect(ptBR.AUTONOMIA_GUIDE.REVISAO[chave]).toBeTruthy();
    });
    expect(ptBR.AUTONOMIA_GUIDE.REVISAO.MOTIVOS.TOQUE).toBe(
      'Toque num motivo para ver as conversas.'
    );
  });
});
