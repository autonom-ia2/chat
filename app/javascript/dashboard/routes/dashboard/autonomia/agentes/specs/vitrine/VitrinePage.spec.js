import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import VitrinePage from '../../vitrine/pages/VitrinePage.vue';
import { FERRAMENTAS } from '../../vitrine/catalogo';

// #2939 — a vitrine com os cards Premium dentro dos grupos do assunto: a legenda do selo só aparece com card Premium
// na tela, a busca "premium" ainda acha os 7, nenhum grupo fica vazio sem eles (flag 44 desligada) e, em cada grupo,
// os grátis vêm antes dos Premium. Cópia real em pt_BR; o servidor (`useVitrine`) é simulado.
withFullI18n('pt_BR');

// O catálogo de verdade já lista os Premium no fim: com ele, a ordem na tela sairia certa mesmo sem a página ordenar.
// Aqui os Premium vêm PRIMEIRO no catálogo, para o teste da ordem só passar se a página puser os grátis antes.
vi.mock('../../vitrine/catalogo', async importOriginal => {
  const original = await importOriginal();
  const premiumPrimeiro = [
    ...original.FERRAMENTAS.filter(item => item.premium),
    ...original.FERRAMENTAS.filter(item => !item.premium),
  ];
  return {
    ...original,
    FERRAMENTAS: premiumPrimeiro,
    liberadas: chaves =>
      premiumPrimeiro.filter(
        item => chaves.includes(item.id) && original.oferecida(item.id)
      ),
  };
});

const PREMIUM = FERRAMENTAS.filter(item => item.premium).map(item => item.id);
const TODAS = FERRAMENTAS.filter(item => item.naVitrine !== false).map(
  item => item.id
);
const GRATIS_DO_MES = { gratis: 20, restantes: 20, precos: ['0.09'] };

const store = vi.hoisted(() => ({ dispatch: vi.fn(), agentes: [] }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => store.agentes),
  };
});
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: vi.fn() }),
}));
vi.mock('../../vitrine/useVitrineLigada', async () => {
  const { ref: criar } = await import('vue');
  return { useVitrineLigada: () => ({ camadas: criar([]) }) };
});
vi.mock('../../composables/useFerramentasDelegadas', async () => {
  const { ref: criar } = await import('vue');
  return { useCadastroManual: () => criar(false) };
});
const vitrine = vi.hoisted(() => ({}));
vi.mock('../../vitrine/useVitrine', () => ({ useVitrine: () => vitrine }));

const montadas = [];
const montar = async fontes => {
  Object.assign(vitrine, {
    carregando: ref(false),
    carregada: ref(true),
    erro: ref(''),
    fontes: ref(fontes),
    carregar: vi.fn().mockResolvedValue(),
    tem: vi.fn(() => false),
    premiumDe: vi.fn(id => (PREMIUM.includes(id) ? GRATIS_DO_MES : null)),
    registrarBuscaSemResultado: vi.fn(),
    atualizadoEm: vi.fn(() => '2026-11-11'),
    estaEmPreparacao: vi.fn(() => false),
  });
  const wrapper = mount(VitrinePage, {
    attachTo: document.body,
    global: { stubs: { VitrineDetalhe: true, VitrineEscolherAgente: true } },
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

const legenda = wrapper => wrapper.find('[data-vitrine-legenda-premium]');
const cartoesDe = (wrapper, raiz = '') =>
  wrapper
    .findAll(`${raiz} [data-vitrine-cartao]`.trim())
    .map(cartao => cartao.attributes('data-vitrine-cartao'));

beforeEach(() => {
  store.agentes = [{ id: 1, name: 'Ana', agent_type: 'support' }];
  store.dispatch.mockReset().mockResolvedValue();
});
afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('VitrinePage · Premium dentro dos grupos', () => {
  it('shows the Premium legend, with the free lookups from the server, when a Premium card is on screen', async () => {
    const wrapper = await montar(TODAS);
    expect(legenda(wrapper).exists()).toBe(true);
    expect(legenda(wrapper).text()).toContain(
      'Consulta mais completa. Cada uma tem 20 grátis por mês.'
    );
    expect(wrapper.find('[data-vitrine-grupo="PREMIUM"]').exists()).toBe(false);
  });

  it('searching "premium" still finds the 7 Premium cards, and only them', async () => {
    const wrapper = await montar(TODAS);
    await wrapper.find('[data-vitrine-busca]').setValue('premium');
    expect(cartoesDe(wrapper).sort()).toEqual([...PREMIUM].sort());
  });

  it('a group without Premium (Saúde) hides the legend', async () => {
    const wrapper = await montar(TODAS);
    await wrapper.find('[data-vitrine-filtro="SAUDE"]').trigger('click');
    expect(cartoesDe(wrapper, '[data-vitrine-grupo="SAUDE"]').length).toBe(4);
    expect(legenda(wrapper).exists()).toBe(false);
  });

  it('without the 7 Premium (flag off) no group is left empty and there is no legend', async () => {
    const wrapper = await montar(TODAS.filter(id => !PREMIUM.includes(id)));
    expect(legenda(wrapper).exists()).toBe(false);
    const grupos = wrapper.findAll('[data-vitrine-grupo]');
    expect(grupos.length).toBeGreaterThan(0);
    grupos.forEach(grupo =>
      expect(grupo.findAll('[data-vitrine-cartao]').length).toBeGreaterThan(0)
    );
    expect(cartoesDe(wrapper).some(id => PREMIUM.includes(id))).toBe(false);
  });

  it('inside each group, the free cards come before the Premium ones, even when the catalog lists the Premium first', async () => {
    const wrapper = await montar(TODAS);
    expect(FERRAMENTAS[0].premium).toBe(true);
    expect(cartoesDe(wrapper, '[data-vitrine-grupo="PESSOAS"]')).toEqual([
      'cnpj',
      'cpf',
      'certidoes_empresa',
      'raio_x_empresa',
      'conferir_pessoa',
    ]);
    expect(cartoesDe(wrapper, '[data-vitrine-grupo="LUGAR"]')).toEqual([
      'cep',
      'cidades',
      'localizacao',
      'ddd',
      'geracao_solar',
      'risco_endereco',
      'imovel_rural',
    ]);
  });
});
