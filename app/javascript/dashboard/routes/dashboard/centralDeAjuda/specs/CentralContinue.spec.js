import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import CentralContinue from '../components/CentralContinue.vue';

const trilha = {
  carregando: ref(false),
  erro: ref(false),
  passos: ref([]),
  resolvidos: ref(2),
  total: ref(9),
  percentual: ref(22),
  carregar: vi.fn(),
};
const isAdmin = ref(true);
const push = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin }),
}));
vi.mock('dashboard/composables/useOnboardingTrail', () => ({
  useOnboardingTrail: () => trilha,
}));

const FEITO = {
  id: 'perfil',
  titulo: 'Perfil',
  status: 'feito',
  artigo: '00.02',
};
const PASSO = {
  id: 'canal',
  titulo: 'Conectar um canal',
  por_que: 'Sem canal, nenhuma conversa chega.',
  status: 'pendente',
  artigo: '00.04',
  video: { poster: '/central-de-ajuda/videos/00.04.jpg' },
};
const AGENTE = {
  id: 'agente_ia',
  titulo: 'Criar o agente de IA',
  status: 'pendente',
  artigo: '00.08',
};

const capitulos = ids => [
  { id: '00', titulo: 'Primeiros passos', artigos: ids.map(id => ({ id })) },
];

const montar = (ids = ['00.02', '00.04', '00.08']) =>
  mount(CentralContinue, {
    props: { capitulos: capitulos(ids) },
    global: {
      stubs: {
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

// O bloco fica na página com v-show (o CI de e-mail barra v-if na raiz): escondido e sem conteúdo montado.
const expectEscondido = wrapper => {
  expect(wrapper.find('section').attributes('style')).toContain(
    'display: none'
  );
  expect(wrapper.find('h2').exists()).toBe(false);
};

describe('CentralContinue', () => {
  beforeEach(() => {
    trilha.carregando.value = false;
    trilha.erro.value = false;
    trilha.passos.value = [FEITO, PASSO, AGENTE];
    isAdmin.value = true;
    push.mockClear();
  });

  it('mostra o próximo passo e abre o artigo dele', async () => {
    const tela = montar();

    expect(tela.text()).toContain('Conectar um canal');
    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.X_DE_Y'
    );
    expect(tela.find('img').attributes('src')).toBe(PASSO.video.poster);

    await tela.findAll('button')[0].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: '00-04' },
    });
  });

  // A conta sem o recurso do passo não enxerga o artigo dele: o botão daria em "não encontrado".
  it('pula o passo pendente cujo artigo não veio para a conta', async () => {
    const tela = montar(['00.02', '00.08']);

    expect(tela.text()).not.toContain('Conectar um canal');
    expect(tela.text()).toContain('Criar o agente de IA');

    await tela.findAll('button')[0].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: '00-08' },
    });
  });

  it('some quando nenhum passo pendente tem artigo visível para a conta', () => {
    trilha.passos.value = [FEITO, AGENTE];

    expectEscondido(montar(['00.02', '00.04']));
  });

  it('some quando a trilha está completa', () => {
    trilha.passos.value = [FEITO];

    expectEscondido(montar());
  });

  it('some quando a trilha deu erro', () => {
    trilha.erro.value = true;

    expectEscondido(montar());
  });

  it('só o administrador vê o link para todos os passos', () => {
    isAdmin.value = false;

    expect(montar().text()).not.toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.VER_TODOS'
    );
  });
});
