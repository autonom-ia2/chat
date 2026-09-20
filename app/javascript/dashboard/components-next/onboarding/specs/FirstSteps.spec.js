import { mount, flushPromises } from '@vue/test-utils';
import FirstSteps from '../FirstSteps.vue';
import OnboardingProgressAPI from 'dashboard/api/onboardingProgress';

vi.mock('dashboard/api/onboardingProgress', () => ({
  default: { get: vi.fn(), skip: vi.fn(), resume: vi.fn() },
}));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) =>
      params ? `${key}|${Object.values(params).join(',')}` : key,
  }),
}));

const alerta = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alerta(...args),
}));

vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentAccountId: 7 } }),
}));

const atualizarUISettings = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings: atualizarUISettings }),
}));

let guiaDisponivel = true;
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({
    value: () => ({ autonomia_guide_available: guiaDisponivel }),
  }),
}));

const passo = (id, ordem, status, extra = {}) => ({
  id,
  ordem,
  status,
  titulo: `Título ${id}`,
  por_que: `Por que ${id}`,
  rota: `rota_${id}`,
  rota_params: {},
  pulavel: false,
  pre_requisitos: [],
  ...extra,
});

const TRILHA = [
  passo('perfil', 0, 'feito'),
  passo('chave_ia', 1, 'pendente', {
    rota: 'settings_applications_integration',
    rota_params: { integration_id: 'crm_kanban_ai' },
    pre_requisitos: ['Conta na OpenAI com crédito'],
  }),
  passo('canal', 2, 'pendente'),
  passo('equipe', 5, 'pendente', { pulavel: true }),
];

const montar = async (passos = TRILHA) => {
  OnboardingProgressAPI.get.mockResolvedValue({ data: { passos } });
  const wrapper = mount(FirstSteps, {
    global: {
      stubs: {
        Spinner: true,
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const botoes = (wrapper, texto) =>
  wrapper.findAll('button').filter(botao => botao.text() === texto);

describe('FirstSteps', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    guiaDisponivel = true;
  });

  it('mostra o progresso contando feitos e pulados', async () => {
    const wrapper = await montar();

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.PROGRESS|1,4');
    expect(
      wrapper.find('[role="progressbar"]').attributes('aria-valuenow')
    ).toBe('25');
  });

  it('conta o passo pulado como resolvido, e marca na lista', async () => {
    const wrapper = await montar([
      passo('perfil', 0, 'feito'),
      passo('chave_ia', 1, 'pendente'),
      passo('equipe', 5, 'pulado', { pulavel: true }),
    ]);

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.PROGRESS|2,3');
    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.STATUS.SKIPPED');
    expect(wrapper.findAll('li')[2].html()).toContain('i-lucide-circle-slash');
  });

  it('põe em foco o primeiro passo pendente, e só ele mostra pré-requisitos', async () => {
    const wrapper = await montar();
    const cartoes = wrapper.findAll('li');

    expect(cartoes[1].classes().join(' ')).toContain('border-n-brand');
    expect(cartoes[1].text()).toContain('Conta na OpenAI com crédito');
    expect(cartoes[2].classes().join(' ')).not.toContain('border-n-brand');
  });

  it('leva à tela certa, com os parâmetros da rota', async () => {
    const wrapper = await montar();

    await botoes(wrapper, 'ONBOARDING_TRAIL.DO_IT')[0].trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'settings_applications_integration',
      params: { accountId: 7, integration_id: 'crm_kanban_ai' },
    });
  });

  it('só oferece deixar para depois nos passos puláveis', async () => {
    const wrapper = await montar();

    expect(botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')).toHaveLength(1);
  });

  it('pula o passo e recarrega a trilha', async () => {
    const wrapper = await montar();
    OnboardingProgressAPI.skip.mockResolvedValue({});

    await botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')[0].trigger('click');
    await flushPromises();

    expect(OnboardingProgressAPI.skip).toHaveBeenCalledWith('equipe');
    expect(OnboardingProgressAPI.get).toHaveBeenCalledTimes(2);
  });

  it('avisa quando não consegue pular', async () => {
    const wrapper = await montar();
    OnboardingProgressAPI.skip.mockRejectedValue(new Error('falhou'));

    await botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')[0].trigger('click');
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith('ONBOARDING_TRAIL.SKIP_ERROR');
  });

  it('abre o Guia pelo "Estou travado", só no passo em foco', async () => {
    const wrapper = await montar();

    const travado = botoes(wrapper, 'ONBOARDING_TRAIL.STUCK');
    expect(travado).toHaveLength(1);

    await travado[0].trigger('click');

    expect(atualizarUISettings).toHaveBeenCalledWith({
      is_autonomia_guide_panel_open: true,
      is_autonomia_copilot_panel_open: false,
    });
  });

  it('esconde o "Estou travado" quando o Guia não está disponível', async () => {
    guiaDisponivel = false;
    const wrapper = await montar();

    expect(botoes(wrapper, 'ONBOARDING_TRAIL.STUCK')).toHaveLength(0);
  });

  it('comemora quando o essencial está pronto', async () => {
    const wrapper = await montar([
      passo('perfil', 0, 'feito'),
      passo('chave_ia', 1, 'feito'),
      passo('canal', 2, 'feito'),
      passo('primeira_resposta', 3, 'feito'),
      passo('funil', 4, 'feito'),
      passo('equipe', 5, 'pendente', { pulavel: true }),
    ]);

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.DONE_TITLE');
    expect(wrapper.text()).not.toContain('ONBOARDING_TRAIL.TITLE');
  });

  it('avisa quando a trilha não carrega', async () => {
    OnboardingProgressAPI.get.mockRejectedValue(new Error('offline'));
    const wrapper = mount(FirstSteps, {
      global: { stubs: { Spinner: true, Button: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.LOAD_ERROR');
  });
});
