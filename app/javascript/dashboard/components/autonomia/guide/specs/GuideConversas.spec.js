import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideConversas from '../GuideConversas.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { conversas: vi.fn(), apagarConversa: vi.fn() },
}));

// #861 — as conversas anteriores com o Guia: abrir e apagar (com confirmação,
// porque apagar não tem desfazer).
const conversa = (id, titulo) => ({
  id,
  titulo,
  atualizada_em: new Date().toISOString(),
  turnos: 2,
});

// O diálogo de verdade abre um <dialog> nativo; aqui basta saber que abriu e
// poder confirmar.
const DialogStub = {
  props: ['title', 'description', 'confirmButtonLabel'],
  emits: ['confirm', 'close'],
  data: () => ({ aberto: false }),
  methods: {
    open() {
      this.aberto = true;
    },
    close() {
      this.aberto = false;
      this.$emit('close');
    },
  },
  template:
    '<div v-if="aberto" data-dialogo>{{ title }} {{ description }}<button data-confirmar @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
};

const montar = (props = {}) =>
  mount(GuideConversas, {
    props,
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
      directives: { tooltip: {} },
      stubs: {
        Dialog: DialogStub,
        Button: {
          props: ['label', 'ariaLabel'],
          emits: ['click'],
          template:
            '<button :aria-label="ariaLabel" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('GuideConversas', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('lista as conversas, e tocar numa abre', async () => {
    AutonomiaGuideAPI.conversas.mockResolvedValue({
      data: {
        conversas: [conversa(1, 'Quantos funis?'), conversa(2, 'Caixas')],
      },
    });
    const wrapper = montar({ conversaAtual: 2 });
    await flushPromises();

    const linhas = wrapper.findAll('[data-conversa]');
    expect(linhas.map(linha => linha.text())).toEqual([
      expect.stringContaining('Quantos funis?'),
      expect.stringContaining('Caixas'),
    ]);
    expect(linhas[1].attributes('aria-current')).toBe('true');

    await linhas[0].trigger('click');
    expect(wrapper.emitted('abrir')).toEqual([[1]]);
  });

  it('sem conversa, diz que elas ficam guardadas até a pessoa apagar', async () => {
    AutonomiaGuideAPI.conversas.mockResolvedValue({
      data: { conversas: [] },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.HISTORY.EMPTY');
    expect(wrapper.text()).not.toContain('dias');
  });

  it('erro ao carregar mostra o motivo e deixa tentar de novo', async () => {
    AutonomiaGuideAPI.conversas
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValueOnce({ data: { conversas: [conversa(1, 'Oi')] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.HISTORY.LOAD_FAILED');
    const tentar = wrapper
      .findAll('button')
      .find(botao => botao.text() === 'AUTONOMIA_GUIDE.HISTORY.RETRY');
    await tentar.trigger('click');
    await flushPromises();

    expect(wrapper.findAll('[data-conversa]')).toHaveLength(1);
  });

  it('apagar pede confirmação, e só confirmado apaga', async () => {
    AutonomiaGuideAPI.conversas.mockResolvedValue({
      data: { conversas: [conversa(1, 'Oi')] },
    });
    AutonomiaGuideAPI.apagarConversa.mockResolvedValue({});
    const wrapper = montar();
    await flushPromises();

    await wrapper
      .find('[aria-label^="AUTONOMIA_GUIDE.HISTORY.DELETE_NAMED"]')
      .trigger('click');
    expect(AutonomiaGuideAPI.apagarConversa).not.toHaveBeenCalled();
    expect(wrapper.find('[data-dialogo]').text()).toContain(
      'AUTONOMIA_GUIDE.HISTORY.CONFIRM_TEXT'
    );

    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.apagarConversa).toHaveBeenCalledWith(1);
    expect(wrapper.emitted('apagou')).toEqual([[1]]);
    expect(wrapper.findAll('[data-conversa]')).toHaveLength(0);
  });

  it('se apagar falha, a conversa fica e a pessoa é avisada', async () => {
    AutonomiaGuideAPI.conversas.mockResolvedValue({
      data: { conversas: [conversa(1, 'Oi')] },
    });
    AutonomiaGuideAPI.apagarConversa.mockRejectedValue(new Error('x'));
    const wrapper = montar();
    await flushPromises();

    await wrapper
      .find('[aria-label^="AUTONOMIA_GUIDE.HISTORY.DELETE_NAMED"]')
      .trigger('click');
    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'AUTONOMIA_GUIDE.HISTORY.DELETE_FAILED'
    );
    expect(wrapper.findAll('[data-conversa]')).toHaveLength(1);
  });
});
