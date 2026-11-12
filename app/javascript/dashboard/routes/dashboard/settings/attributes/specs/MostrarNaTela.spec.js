import { mount, flushPromises } from '@vue/test-utils';
import EditAttribute from '../EditAttribute.vue';
import AddAttribute from '../AddAttribute.vue';

// #2435 — "Mostrar na tela" nas telas de criar e editar atributo: ligado por
// padrão, e desligado manda oculto_na_tela: true.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const stubs = {
  'woot-modal-header': true,
  'woot-input': true,
  NextButton: true,
  TagInput: true,
  ChoiceSelect: true,
};

const atributo = {
  id: 9,
  attribute_display_name: 'Contador',
  attribute_description: 'Usado pela automação',
  attribute_display_type: 'number',
  attribute_key: 'contador',
  attribute_model: 'contact_attribute',
  attribute_values: [],
  oculto_na_tela: false,
};

const montarEdicao = (selectedAttribute, dispatch) =>
  mount(EditAttribute, {
    props: { selectedAttribute },
    global: { stubs, mocks: { $t: key => key, $store: { dispatch } } },
  });

const chave = wrapper => wrapper.find('[role="switch"]');

describe('Mostrar na tela — editar atributo', () => {
  it('desligar e salvar manda oculto_na_tela: true', async () => {
    const dispatch = vi.fn().mockResolvedValue();
    const wrapper = montarEdicao(atributo, dispatch);
    expect(chave(wrapper).attributes('aria-checked')).toBe('true');
    expect(wrapper.text()).toContain('ATTRIBUTES_MGMT.MOSTRAR_NA_TELA.AJUDA');

    await chave(wrapper).trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/update',
      expect.objectContaining({ id: 9, oculto_na_tela: true })
    );
  });

  it('o atributo fora da tela abre com a chave desligada, e religar mostra de novo', async () => {
    const dispatch = vi.fn().mockResolvedValue();
    const wrapper = montarEdicao(
      { ...atributo, oculto_na_tela: true },
      dispatch
    );
    expect(chave(wrapper).attributes('aria-checked')).toBe('false');

    await chave(wrapper).trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/update',
      expect.objectContaining({ oculto_na_tela: false })
    );
  });
});

describe('Mostrar na tela — criar atributo', () => {
  it('o atributo novo nasce na tela', () => {
    expect(AddAttribute.data.call({ selectedAttributeModelTab: 1 })).toEqual(
      expect.objectContaining({ mostrarNaTela: true })
    );
  });
});
