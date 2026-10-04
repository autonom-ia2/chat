import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideAnotei from '../GuideAnotei.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { apagarMemoria: vi.fn() },
}));

// #933 — o chip "Anotei: …" sob a resposta, com "Esquecer".
const montar = () =>
  mount(GuideAnotei, {
    props: { lembranca: { id: 7, texto: 'Fala curto', de_quem: 'minha' } },
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
      stubs: {
        Button: {
          props: ['label', 'ariaLabel'],
          emits: ['click'],
          template:
            '<button :aria-label="ariaLabel" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('GuideAnotei', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('mostra o que foi anotado', () => {
    expect(montar().text()).toContain(
      'AUTONOMIA_GUIDE.MEMORY.NOTED:{"texto":"Fala curto"}'
    );
  });

  it('esquecer apaga a anotação e avisa quem mostra o chip', async () => {
    AutonomiaGuideAPI.apagarMemoria.mockResolvedValue({});
    const wrapper = montar();

    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.apagarMemoria).toHaveBeenCalledWith(7);
    expect(wrapper.emitted('esqueceu')).toEqual([[7]]);
  });

  it('se esquecer falha, o chip fica e a pessoa é avisada', async () => {
    AutonomiaGuideAPI.apagarMemoria.mockRejectedValue(new Error('x'));
    const wrapper = montar();

    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('esqueceu')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith(
      'AUTONOMIA_GUIDE.MEMORY.DELETE_FAILED'
    );
  });
});
