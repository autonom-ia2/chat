import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideMemoria from '../GuideMemoria.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: {
    memorias: vi.fn(),
    corrigirMemoria: vi.fn(),
    apagarMemoria: vi.fn(),
  },
}));

// #933 — "O que eu sei": o que o Guia lembra da pessoa e da corretora, com
// corrigir no lugar e apagar com confirmação.
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

const montar = () =>
  mount(GuideMemoria, {
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
      stubs: {
        Dialog: DialogStub,
        TextArea: {
          props: ['modelValue', 'label'],
          emits: ['update:modelValue'],
          template:
            '<textarea data-rascunho :aria-label="label" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
        Button: {
          props: ['label', 'ariaLabel', 'disabled'],
          emits: ['click'],
          template:
            '<button :aria-label="ariaLabel" :disabled="disabled" v-bind="$attrs" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const resposta = (extra = {}) => ({
  data: {
    pessoais: [{ id: 3, texto: 'Prefere respostas curtas' }],
    corretora: [
      { id: 7, texto: 'Funil do Zé = funil Comercial', autor: 'Ana' },
    ],
    pode_editar_corretora: true,
    limites: { pessoais: 12, corretora: 20 },
    ...extra,
  },
});

const botao = (wrapper, texto) =>
  wrapper.findAll('button').find(item => item.text() === texto);

describe('GuideMemoria', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('mostra as duas seções com o que o Guia lembra', async () => {
    AutonomiaGuideAPI.memorias.mockResolvedValue(resposta());
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-secao="pessoais"]').text()).toContain(
      'Prefere respostas curtas'
    );
    const corretora = wrapper.find('[data-secao="corretora"]');
    expect(corretora.text()).toContain('Funil do Zé = funil Comercial');
    expect(corretora.text()).toContain('AUTONOMIA_GUIDE.MEMORY.TAUGHT_BY');
    expect(
      wrapper.findAll('[aria-label^="AUTONOMIA_GUIDE.MEMORY.EDIT_NAMED"]')
    ).toHaveLength(2);
  });

  it('vazio ensina a primeira frase, e tocar num exemplo manda para o Guia', async () => {
    AutonomiaGuideAPI.memorias.mockResolvedValue(
      resposta({ pessoais: [], corretora: [] })
    );
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.findAll('[data-vazio]')).toHaveLength(2);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.MEMORY.EMPTY_TEXT');

    await wrapper.find('[data-exemplo]').trigger('click');
    expect(wrapper.emitted('perguntar')).toEqual([
      ['AUTONOMIA_GUIDE.MEMORY.EXAMPLE_YOU_1'],
    ]);
  });

  it('quem não administra vê as da corretora sem os botões, e sabe quem pode mudar', async () => {
    AutonomiaGuideAPI.memorias.mockResolvedValue(
      resposta({ pode_editar_corretora: false })
    );
    const wrapper = montar();
    await flushPromises();

    const corretora = wrapper.find('[data-secao="corretora"]');
    expect(corretora.findAll('[aria-label]')).toHaveLength(0);
    expect(corretora.find('[data-so-admin]').exists()).toBe(true);
    expect(wrapper.find('[data-secao="pessoais"] [aria-label]').exists()).toBe(
      true
    );
  });

  it('corrige no lugar e salva', async () => {
    AutonomiaGuideAPI.memorias.mockResolvedValue(resposta());
    AutonomiaGuideAPI.corrigirMemoria.mockResolvedValue({
      data: { id: 3, texto: 'Prefere tópicos' },
    });
    const wrapper = montar();
    await flushPromises();

    await wrapper
      .find('[aria-label^="AUTONOMIA_GUIDE.MEMORY.EDIT_NAMED"]')
      .trigger('click');
    await wrapper.find('[data-rascunho]').setValue('Prefere tópicos');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(AutonomiaGuideAPI.corrigirMemoria).toHaveBeenCalledWith(
      3,
      'Prefere tópicos'
    );
    expect(wrapper.find('[data-rascunho]').exists()).toBe(false);
    expect(wrapper.find('[data-secao="pessoais"]').text()).toContain(
      'Prefere tópicos'
    );
    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.MEMORY.SAVED');
  });

  it('se salvar falha, o texto fica para a pessoa tentar de novo', async () => {
    AutonomiaGuideAPI.memorias.mockResolvedValue(resposta());
    AutonomiaGuideAPI.corrigirMemoria.mockRejectedValue(new Error('x'));
    const wrapper = montar();
    await flushPromises();

    await wrapper
      .find('[aria-label^="AUTONOMIA_GUIDE.MEMORY.EDIT_NAMED"]')
      .trigger('click');
    await wrapper.find('[data-rascunho]').setValue('Outra coisa');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.MEMORY.SAVE_FAILED');
    expect(wrapper.find('[data-rascunho]').element.value).toBe('Outra coisa');
  });

  it('apagar pede confirmação, e só confirmado apaga', async () => {
    AutonomiaGuideAPI.memorias.mockResolvedValue(resposta());
    AutonomiaGuideAPI.apagarMemoria.mockResolvedValue({});
    const wrapper = montar();
    await flushPromises();

    await wrapper
      .find('[aria-label^="AUTONOMIA_GUIDE.MEMORY.DELETE_NAMED"]')
      .trigger('click');
    expect(AutonomiaGuideAPI.apagarMemoria).not.toHaveBeenCalled();
    expect(wrapper.find('[data-dialogo]').text()).toContain(
      'AUTONOMIA_GUIDE.MEMORY.CONFIRM_TEXT'
    );

    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.apagarMemoria).toHaveBeenCalledWith(3);
    expect(wrapper.find('[data-secao="pessoais"] [data-vazio]').exists()).toBe(
      true
    );
    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.MEMORY.FORGOTTEN');
  });

  it('erro ao carregar diz o que fazer e deixa tentar de novo', async () => {
    AutonomiaGuideAPI.memorias
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValueOnce(resposta());
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain(
      'AUTONOMIA_GUIDE.MEMORY.LOAD_FAILED'
    );
    await botao(wrapper, 'AUTONOMIA_GUIDE.MEMORY.RETRY').trigger('click');
    await flushPromises();

    expect(wrapper.findAll('[data-memoria]')).toHaveLength(2);
  });
});
