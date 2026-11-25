import { mount, flushPromises } from '@vue/test-utils';
import ProntosParaContratar from '../../components/ProntosParaContratar.vue';
import AgenteEscolherPage from '../../pages/AgenteEscolherPage.vue';

// #3211 (Tarefa 26) — "Vendem sozinhos": os agentes prontos que a corretora contrata, na página "Criar agente", dentro
// do herói e antes dos ramos (mockup aprovado, estado 01). Quais aparecem é decisão do servidor (useContratados).
const estado = vi.hoisted(() => ({ podeGerenciar: true }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => estado.podeGerenciar) };
});
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    'accounts/getAccount': () => () => ({ autonomia_agents_fase2: false }),
    getCurrentAccountId: () => 1,
  };
  return { useMapGetter: nome => computed(() => getters[nome]()) };
});
const router = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => router }));
const jornada = vi.hoisted(() => ({
  modelosDeRamo: vi.fn(() => Promise.resolve({ data: { modelos: [] } })),
}));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornada }));
const contratados = vi.hoisted(() => ({
  lista: vi.fn(() => Promise.resolve({ data: { modelos: [] } })),
}));
vi.mock('dashboard/api/autonomia/contratados', () => ({
  default: contratados,
}));

const UNIVERSAL = 'seguro_viagem_universal';

const montarPagina = async () => {
  const wrapper = mount(AgenteEscolherPage);
  await flushPromises();
  return wrapper;
};

describe('ProntosParaContratar (#3211)', () => {
  beforeEach(() => {
    estado.podeGerenciar = true;
  });

  it('shows the section title and the Universal card, and opens it by its key', async () => {
    const wrapper = mount(ProntosParaContratar, {
      props: { modelos: [UNIVERSAL], podeUsar: true },
    });

    expect(wrapper.get('h2').text()).toBe('AGENTS.CONTRATADOS.AREA.TITULO');
    expect(wrapper.text()).toContain('AGENTS.CONTRATADOS.AREA.TEXTO');
    const cartoes = wrapper.findAll('[data-contratado]');
    expect(cartoes).toHaveLength(1);
    expect(cartoes[0].get('h3').text()).toBe(
      'AGENTS.CONTRATADOS.CARTAO.TITULO'
    );
    expect(cartoes[0].text()).toContain('AGENTS.CONTRATADOS.CARTAO.PRECISA');

    const botao = wrapper.get('[data-ver-contratado]');
    expect(botao.text()).toContain('AGENTS.CONTRATADOS.CARTAO.VER');
    expect(botao.attributes('aria-label')).toBe(
      'AGENTS.CONTRATADOS.CARTAO.VER_ARIA'
    );
    await botao.trigger('click');
    expect(wrapper.emitted('abrir')).toEqual([[UNIVERSAL]]);
  });

  it('shows the card without the button to whoever cannot manage agents', () => {
    const wrapper = mount(ProntosParaContratar, {
      props: { modelos: [UNIVERSAL], podeUsar: false },
    });

    expect(wrapper.find('[data-contratado]').exists()).toBe(true);
    expect(wrapper.find('[data-ver-contratado]').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });

  describe('on the "Criar agente" page', () => {
    it('does not render the section when the server lists no model', async () => {
      const wrapper = await montarPagina();

      expect(contratados.lista).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-contratados]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('AGENTS.CONTRATADOS');
    });

    it('does not render a card for a model the screen does not know', async () => {
      contratados.lista.mockResolvedValueOnce({
        data: { modelos: ['outro_modelo'] },
      });
      const wrapper = await montarPagina();

      expect(wrapper.find('[data-contratados]').exists()).toBe(false);
    });

    it('puts the section inside the navy block, before the ready-made branches, and goes to the model page', async () => {
      contratados.lista.mockResolvedValueOnce({
        data: { modelos: [UNIVERSAL] },
      });
      jornada.modelosDeRamo.mockResolvedValueOnce({
        data: { modelos: ['seguro_auto'] },
      });
      const wrapper = await montarPagina();

      const heroi = wrapper.get('[data-heroi]');
      const secoes = heroi.findAll('[data-contratados], [data-ramos]');
      expect(secoes.map(secao => Object.keys(secao.attributes()))).toEqual([
        expect.arrayContaining(['data-contratados']),
        expect.arrayContaining(['data-ramos']),
      ]);

      await heroi.get('[data-ver-contratado]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_contratado_modelo',
        params: { modelo: UNIVERSAL },
      });
      expect(wrapper.emitted('escolher')).toBeUndefined();
    });

    it('shows the card without the button to whoever only views', async () => {
      estado.podeGerenciar = false;
      contratados.lista.mockResolvedValueOnce({
        data: { modelos: [UNIVERSAL] },
      });
      const wrapper = await montarPagina();

      expect(wrapper.find('[data-contratados]').exists()).toBe(true);
      expect(wrapper.find('[data-ver-contratado]').exists()).toBe(false);
    });
  });
});
