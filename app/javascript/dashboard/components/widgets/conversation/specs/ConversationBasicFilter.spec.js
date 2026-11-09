import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import ConversationBasicFilter from '../ConversationBasicFilter.vue';

const uiSettings = ref({});
const updateUISettings = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings }),
}));
const statusDaTela = ref('all');
vi.mock('dashboard/composables/store.js', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: nome =>
    nome === 'getChatStatusFilter' ? statusDaTela : ref('latest'),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const montar = () =>
  mount(ConversationBasicFilter, {
    props: { isOnExpandedLayout: false },
    global: {
      mocks: { $t: chave => chave },
      directives: { tooltip: {}, onClickOutside: {} },
      stubs: {
        NextButton: {
          emits: ['click'],
          template: '<button @click="$emit(\'click\')" />',
        },
        SelectMenu: {
          name: 'SelectMenu',
          emits: ['update:modelValue'],
          template: '<div />',
        },
      },
    },
  });

// O filtro do link (Números, Seus posts #2209) abre num status que não é escolha da pessoa.
describe('ConversationBasicFilter: trocar a ordem com o filtro do link', () => {
  beforeEach(() => {
    updateUISettings.mockClear();
    statusDaTela.value = 'all';
  });

  const trocarAOrdem = async () => {
    const wrapper = montar();
    await wrapper.find('button').trigger('click');
    wrapper
      .findAllComponents({ name: 'SelectMenu' })[1]
      .vm.$emit('update:modelValue', 'created_at_desc');
  };

  it('grava o status salvo da pessoa, não o da tela', async () => {
    uiSettings.value = { conversations_filter_by: { status: 'pending' } };
    await trocarAOrdem();

    expect(updateUISettings).toHaveBeenCalledWith({
      conversations_filter_by: {
        status: 'pending',
        order_by: 'created_at_desc',
      },
    });
  });

  it('sem status salvo, grava Abertas', async () => {
    uiSettings.value = {};
    await trocarAOrdem();

    expect(updateUISettings).toHaveBeenCalledWith({
      conversations_filter_by: { status: 'open', order_by: 'created_at_desc' },
    });
  });
});
