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
  useStore: () => ({
    getters: { getCurrentAccountId: 7, getCurrentUser: { name: 'Rodrigo' } },
  }),
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

const ETAPA = {
  perfil: 'ligar',
  chave_ia: 'ligar',
  canal: 'ligar',
  equipe: 'organizar',
  funil: 'organizar',
  campanha: 'crescer',
};

const passo = (id, ordem, status, extra = {}) => ({
  id,
  ordem,
  status,
  titulo: `Título ${id}`,
  por_que: `Por que ${id}`,
  acao: `Ação ${id}`,
  rota: `rota_${id}`,
  rota_params: {},
  etapa: ETAPA[id] || 'ligar',
  minutos: 5,
  artigo: '00.03',
  video: null,
  depende_de: null,
  pulavel: false,
  pre_requisitos: [],
  ...extra,
});

const VIDEO = {
  arquivo: '/central-de-ajuda/videos/00.03.mp4',
  legenda: '/central-de-ajuda/videos/00.03.vtt',
  poster: '/central-de-ajuda/videos/00.03.jpg',
};

const TRILHA = [
  passo('perfil', 0, 'feito'),
  passo('chave_ia', 1, 'pendente', {
    rota: 'settings_applications_integration',
    rota_params: { integration_id: 'crm_kanban_ai' },
    pre_requisitos: ['Conta na OpenAI com crédito'],
    video: VIDEO,
  }),
  passo('canal', 2, 'pendente', { minutos: 10 }),
  passo('equipe', 5, 'pendente', {
    pulavel: true,
    minutos: 3,
    depende_de: { id: 'canal', titulo: 'Título canal', pendente: true },
  }),
];

const montar = async (passos = TRILHA) => {
  OnboardingProgressAPI.get.mockResolvedValue({ data: { passos } });
  const wrapper = mount(FirstSteps, {
    global: {
      stubs: {
        Spinner: true,
        VideoDoTrajeto: {
          props: ['video'],
          template: '<video :src="video.arquivo" />',
        },
        RouterLink: {
          props: ['to'],
          template: '<a :data-ref="to.params.ref"><slot /></a>',
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
  return wrapper;
};

const botoes = (wrapper, texto) =>
  wrapper.findAll('button').filter(botao => botao.text() === texto);

const painel = wrapper => wrapper.find('article');

const linha = (wrapper, id) =>
  wrapper
    .findAll('li button')
    .find(botao => botao.text().includes(`Título ${id}`));

describe('FirstSteps', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    guiaDisponivel = true;
  });

  it('rola quando a trilha não cabe na tela', async () => {
    const wrapper = await montar();

    // O <main> do painel tem overflow-hidden: sem rolagem própria, os últimos
    // passos ficam inalcançáveis em tela de altura comum.
    const raiz = wrapper.find('section');
    expect(raiz.classes()).toContain('overflow-y-auto');
    expect(raiz.classes()).toContain('h-full');
  });

  it('cumprimenta pelo nome e mostra o progresso contando feitos e pulados', async () => {
    const wrapper = await montar();

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.GREETING|Rodrigo');
    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.PROGRESS|1,4');
    expect(
      wrapper.find('[role="progressbar"]').attributes('aria-valuenow')
    ).toBe('25');
  });

  it('soma o tempo só dos passos que faltam', async () => {
    const wrapper = await montar();

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.REMAINING|18');
  });

  it('agrupa a trilha nas etapas, com o progresso de cada uma', async () => {
    const wrapper = await montar();

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.ETAPAS.ligar');
    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.ETAPAS.organizar');
    expect(wrapper.text()).not.toContain('ONBOARDING_TRAIL.ETAPAS.crescer');
    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.PROGRESS|1,3');
  });

  it('conta o passo pulado como resolvido, e marca na lista', async () => {
    const wrapper = await montar([
      passo('perfil', 0, 'feito'),
      passo('chave_ia', 1, 'pendente'),
      passo('equipe', 5, 'pulado', { pulavel: true }),
    ]);

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.PROGRESS|2,3');
    expect(linha(wrapper, 'equipe').text()).toContain(
      'ONBOARDING_TRAIL.STATUS.SKIPPED'
    );
    expect(linha(wrapper, 'equipe').attributes('disabled')).toBeDefined();
  });

  it('abre no painel o primeiro passo pendente, com o que separar antes', async () => {
    const wrapper = await montar();

    expect(painel(wrapper).text()).toContain('ONBOARDING_TRAIL.NEXT_STEP');
    expect(painel(wrapper).text()).toContain('Título chave_ia');
    expect(painel(wrapper).text()).toContain('Conta na OpenAI com crédito');
    expect(painel(wrapper).text()).toContain('ONBOARDING_TRAIL.TIME|5');
    expect(linha(wrapper, 'chave_ia').attributes('aria-current')).toBe('step');
  });

  it('tem um único botão principal, com o verbo do passo, que leva à tela certa', async () => {
    const wrapper = await montar();

    expect(botoes(wrapper, 'Ação canal')).toHaveLength(0);
    await botoes(wrapper, 'Ação chave_ia')[0].trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'settings_applications_integration',
      params: { accountId: 7, integration_id: 'crm_kanban_ai' },
    });
  });

  it('mostra o vídeo da Central e o link do artigo no passo que tem vídeo', async () => {
    const wrapper = await montar();

    expect(painel(wrapper).find('video').attributes('src')).toBe(VIDEO.arquivo);
    expect(painel(wrapper).find('a').attributes('data-ref')).toBe('00.03');
    expect(painel(wrapper).text()).toContain('ONBOARDING_TRAIL.READ_ARTICLE');
  });

  it('sem vídeo, aponta o passo a passo escrito', async () => {
    const wrapper = await montar();

    await linha(wrapper, 'canal').trigger('click');

    expect(painel(wrapper).find('video').exists()).toBe(false);
    expect(painel(wrapper).text()).toContain('ONBOARDING_TRAIL.NO_VIDEO');
    expect(painel(wrapper).text()).toContain('ONBOARDING_TRAIL.OPEN_ARTICLE');
  });

  it('abre no painel o passo escolhido na lista', async () => {
    const wrapper = await montar();

    await linha(wrapper, 'canal').trigger('click');

    expect(painel(wrapper).text()).toContain('ONBOARDING_TRAIL.CHOSEN_STEP');
    expect(painel(wrapper).text()).toContain('Título canal');
  });

  it('avisa a dependência pendente sem bloquear o passo', async () => {
    const wrapper = await montar();

    expect(linha(wrapper, 'equipe').text()).toContain(
      'ONBOARDING_TRAIL.WAITS_FOR|Título canal'
    );

    await linha(wrapper, 'equipe').trigger('click');

    expect(painel(wrapper).text()).toContain(
      'ONBOARDING_TRAIL.WAITS_FOR|Título canal'
    );
    expect(botoes(wrapper, 'Ação equipe')).toHaveLength(1);
  });

  it('só oferece pular nos passos puláveis', async () => {
    const wrapper = await montar();

    expect(botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')).toHaveLength(0);

    await linha(wrapper, 'equipe').trigger('click');

    expect(botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')).toHaveLength(1);
  });

  it('pula o passo e recarrega a trilha', async () => {
    const wrapper = await montar();
    OnboardingProgressAPI.skip.mockResolvedValue({});
    await linha(wrapper, 'equipe').trigger('click');

    await botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')[0].trigger('click');
    await flushPromises();

    expect(OnboardingProgressAPI.skip).toHaveBeenCalledWith('equipe');
    expect(OnboardingProgressAPI.get).toHaveBeenCalledTimes(2);
  });

  it('avisa quando não consegue pular', async () => {
    const wrapper = await montar();
    OnboardingProgressAPI.skip.mockRejectedValue(new Error('falhou'));
    await linha(wrapper, 'equipe').trigger('click');

    await botoes(wrapper, 'ONBOARDING_TRAIL.SKIP')[0].trigger('click');
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith('ONBOARDING_TRAIL.SKIP_ERROR');
  });

  it('abre o Guia pelo "Preciso de ajuda"', async () => {
    const wrapper = await montar();

    const ajuda = botoes(wrapper, 'ONBOARDING_TRAIL.HELP');
    expect(ajuda).toHaveLength(1);

    await ajuda[0].trigger('click');

    expect(atualizarUISettings).toHaveBeenCalledWith({
      is_autonomia_guide_panel_open: true,
      is_autonomia_copilot_panel_open: false,
    });
  });

  it('esconde o "Preciso de ajuda" quando o Guia não está disponível', async () => {
    guiaDisponivel = false;
    const wrapper = await montar();

    expect(botoes(wrapper, 'ONBOARDING_TRAIL.HELP')).toHaveLength(0);
  });

  it('comemora quando o essencial está pronto, e mostra o resto a pedido', async () => {
    const wrapper = await montar([
      passo('perfil', 0, 'feito'),
      passo('chave_ia', 1, 'feito'),
      passo('canal', 2, 'feito'),
      passo('primeira_resposta', 3, 'feito'),
      passo('funil', 4, 'feito'),
      passo('equipe', 5, 'pendente', { pulavel: true }),
    ]);

    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.DONE_TITLE');
    expect(wrapper.text()).toContain('ONBOARDING_TRAIL.ESSENTIAL_READY');
    expect(wrapper.find('article').exists()).toBe(false);

    await botoes(wrapper, 'ONBOARDING_TRAIL.SEE_REST')[0].trigger('click');

    expect(painel(wrapper).text()).toContain('Título equipe');
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
