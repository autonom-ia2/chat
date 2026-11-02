import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CuidarDono from '../CuidarDono.vue';
import CuidarLigado from '../CuidarLigado.vue';

// #2487 (PR 3b do #2436): o material só deste post ou anúncio na tela do cuidado. No passo 1, o anexo só aparece ao
// editar um cuidado que já existe; no novo, a linha de "depois de ligar". Logo depois de ligar, "Anexar agora" em
// destaque, com o aviso de que os primeiros comentários são respondidos sem ele.
const api = vi.hoisted(() => ({
  materiais: vi.fn(),
  anexar: vi.fn(),
  tirar: vi.fn(),
}));
vi.mock('dashboard/api/agentesDoPost', () => ({ default: api }));

const painel = (extra = {}) => ({
  network: 'instagram',
  private_available: true,
  care: 'off',
  care_id: null,
  message: 'Oi! O seguro sai a partir de R$ 39.',
  para_quem: 'Quem perguntar o preço',
  phrases: ['Te mandei no privado!'],
  unanswered: 0,
  read_old: false,
  results: { sent: 0, replied: 0, skipped: 0 },
  to_see: [],
  hidden: [],
  writes: true,
  temas: [],
  assunto_proibido: '',
  tom: '',
  ...extra,
});

const i18n = () =>
  createI18n({ legacy: false, locale: 'pt_BR', missingWarn: false });
const montadas = [];
const montar = async (componente, props) => {
  const wrapper = mount(componente, { props, global: { plugins: [i18n()] } });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};
const dono = data => montar(CuidarDono, { data, preview: vi.fn() });
const ligado = (data, extra = {}) =>
  montar(CuidarLigado, { data, canManage: true, ...extra });

describe('#2487 · o material só do post na tela do cuidado', () => {
  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
    api.materiais.mockResolvedValue({ data: { materiais: [] } });
  });
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('passo 1 do cuidado novo: só a linha de depois de ligar, sem anexar', async () => {
    const wrapper = await dono(painel());

    expect(wrapper.find('[data-ia-dono-material-depois]').text()).toContain(
      'DEPOIS_DE_LIGAR'
    );
    expect(wrapper.find('[data-anexar]').exists()).toBe(false);
    expect(api.materiais).not.toHaveBeenCalled();
  });

  it('passo 1 de um cuidado que já existe: anexar ali mesmo', async () => {
    const wrapper = await dono(painel({ care: 'on', care_id: 9 }));

    expect(wrapper.find('[data-anexar]').exists()).toBe(true);
    expect(api.materiais).toHaveBeenCalledWith(9);
  });

  it('sem a IA escrevendo (sem `writes`), o passo 1 fica como antes', async () => {
    const wrapper = await dono(painel({ writes: undefined, care_id: 9 }));

    expect(wrapper.find('[data-ia-dono-material]').exists()).toBe(false);
  });

  it('logo depois de ligar: "Anexar agora" em destaque, com o aviso', async () => {
    const wrapper = await ligado(painel({ care: 'on', care_id: 9 }), {
      started: 'new',
    });

    const destaque = wrapper.get('[data-ia-anexar-agora]');
    expect(destaque.text()).toContain('ANEXAR_AGORA');
    expect(destaque.text()).toContain('AVISO_AGORA');
    expect(destaque.find('[data-anexar]').exists()).toBe(true);
  });

  it('ao abrir o cuidado ligado depois, ou para quem só vê, sem o destaque', async () => {
    const depois = await ligado(painel({ care: 'on', care_id: 9 }));
    const soVe = await ligado(painel({ care: 'on', care_id: 9 }), {
      started: 'new',
      canManage: false,
    });

    expect(depois.find('[data-ia-anexar-agora]').exists()).toBe(false);
    expect(soVe.find('[data-ia-anexar-agora]').exists()).toBe(false);
  });
});
