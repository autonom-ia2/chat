import { flushPromises, mount } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import CampoContato from '../CampoContato.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('@vueuse/core', () => ({ useDebounceFn: fn => fn }));
vi.mock('dashboard/api/contacts', () => ({
  default: { show: vi.fn(), search: vi.fn() },
}));

// Decisão 16 (ex. 11) — o campo do card do tipo contato: busca um contato da
// conta e guarda o id dele; sem editar, mostra o nome.
const ChoiceFalso = {
  props: ['modelValue', 'options', 'ariaLabel', 'placeholder'],
  emits: ['update:modelValue'],
  template:
    '<button type="button" data-escolha :data-valor="modelValue" @click="$emit(\'update:modelValue\', options.at(-1).value)" />',
};
const InputFalso = {
  props: ['modelValue', 'size'],
  emits: ['update:modelValue'],
  template:
    '<input data-busca :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
};

const MARIA = { id: 11, name: 'Maria', phone_number: '+5511900000011' };
const JOAO = { id: 12, name: 'João', email: 'joao@exemplo.com' };

const montar = (valor, props = {}) =>
  mount(CampoContato, {
    props: {
      attribute: { attributeDisplayName: 'Indicado por', value: valor },
      ...props,
    },
    global: {
      stubs: { ChoiceSelect: ChoiceFalso, Input: InputFalso, Button: true },
    },
  });

describe('CampoContato', () => {
  beforeEach(() => {
    ContactAPI.show.mockResolvedValue({ data: { payload: MARIA } });
    ContactAPI.search.mockResolvedValue({ data: { payload: [MARIA, JOAO] } });
  });

  afterEach(() => vi.clearAllMocks());

  it('mostra o contato guardado pelo id, com o nome', async () => {
    const wrapper = montar(11);
    await flushPromises();

    expect(ContactAPI.show).toHaveBeenCalledWith(11);
    expect(wrapper.find('[data-escolha]').attributes('data-valor')).toBe('11');
    expect(
      wrapper.findComponent(ChoiceFalso).props('options')[0]
    ).toMatchObject({ value: 11, label: 'Maria', hint: '+5511900000011' });
  });

  it('busca na conta pelo que a pessoa digita e grava o id escolhido', async () => {
    const wrapper = montar('');
    await wrapper.find('[data-busca]').setValue('jo');
    await flushPromises();

    expect(ContactAPI.search).toHaveBeenCalledWith('jo', 1, 'name');
    await wrapper.find('[data-escolha]').trigger('click');
    expect(wrapper.emitted('update')).toEqual([[12]]);
  });

  it('não busca com menos de duas letras', async () => {
    const wrapper = montar('');
    await wrapper.find('[data-busca]').setValue('j');
    await flushPromises();

    expect(ContactAPI.search).not.toHaveBeenCalled();
  });

  it('a busca sem resultado diz isso', async () => {
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar('');
    await wrapper.find('[data-busca]').setValue('zz');
    await flushPromises();

    expect(wrapper.find('[data-sem-contato]').exists()).toBe(true);
  });

  it('sem editar, mostra o nome; só o 404 diz que o contato foi apagado', async () => {
    const leitura = montar(11, { editavel: false });
    await flushPromises();
    expect(leitura.text()).toBe('Maria');

    ContactAPI.show.mockRejectedValue({ response: { status: 404 } });
    const apagado = montar(99, { editavel: false });
    await flushPromises();
    expect(apagado.text()).toBe('CRM_KANBAN.DRAWER.CARD_FIELDS.CONTATO_SUMIU');

    ContactAPI.show.mockRejectedValue({ response: { status: 500 } });
    const falhou = montar(98, { editavel: false });
    await flushPromises();
    expect(falhou.text()).toBe(
      'CRM_KANBAN.DRAWER.CARD_FIELDS.CONTATO_NAO_CARREGOU'
    );
  });

  it('a resposta de um id antigo que chega depois da troca é descartada', async () => {
    let devolverMaria;
    ContactAPI.show
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            devolverMaria = () => resolve({ data: { payload: MARIA } });
          })
      )
      .mockResolvedValueOnce({ data: { payload: JOAO } });
    const wrapper = montar(11, { editavel: false });
    await wrapper.setProps({
      attribute: { attributeDisplayName: 'Indicado por', value: 12 },
    });
    await flushPromises();
    devolverMaria();
    await flushPromises();

    expect(wrapper.text()).toBe('João');
  });

  it('a busca que falha diz que não deu para buscar, e não "nenhum contato"', async () => {
    ContactAPI.search.mockRejectedValue(new Error('rede'));
    const wrapper = montar('');
    await wrapper.find('[data-busca]').setValue('jo');
    await flushPromises();

    expect(wrapper.find('[data-busca-falhou]').exists()).toBe(true);
    expect(wrapper.find('[data-sem-contato]').exists()).toBe(false);
  });
});
