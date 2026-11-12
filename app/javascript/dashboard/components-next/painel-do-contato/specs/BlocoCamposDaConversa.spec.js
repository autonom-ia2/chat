import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import BlocoCamposDaConversa from '../BlocoCamposDaConversa.vue';
import { criarI18n, criarStore } from './apoio';

// #2538 — os campos da conversa no painel novo: todos os definidos, inclusive
// os vazios; quem opera a conversa edita, quem só lê vê o valor.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

enableAutoUnmount(afterEach);

const definicao = (
  id,
  chave,
  nome,
  modelo = 'conversation_attribute',
  extra = {}
) => ({
  id,
  attribute_key: chave,
  attribute_display_name: nome,
  attribute_display_type: 'text',
  attribute_model: modelo,
  ...extra,
});
const DEFINICOES = [
  definicao(1, 'placa', 'Placa'),
  definicao(2, 'modelo_do_carro', 'Modelo do carro'),
  definicao(3, 'melhor_horario', 'Melhor horário', 'contact_attribute'),
];
const CONVERSA = { id: 42, custom_attributes: { placa: 'ABC1D23' } };

const montar = ({ podeOperar = true, definicoes = DEFINICOES } = {}) => {
  const apoio = criarStore({ definicoes });
  const wrapper = mount(BlocoCamposDaConversa, {
    props: { conversation: CONVERSA, podeOperar },
    global: { plugins: [apoio.store, criarI18n()] },
  });
  return { wrapper, ...apoio };
};

describe('BlocoCamposDaConversa', () => {
  it('lista os campos da conversa, inclusive os vazios, e não os do contato', () => {
    const { wrapper } = montar();

    expect(wrapper.text()).toContain('Campos da conversa');
    expect(wrapper.text()).toContain('Placa');
    expect(wrapper.text()).toContain('ABC1D23');
    expect(wrapper.text()).toContain('Modelo do carro');
    expect(wrapper.text()).not.toContain('Melhor horário');
    expect(wrapper.findAll('li')).toHaveLength(2);
  });

  it('some quando a conta não tem campo de conversa', () => {
    const { wrapper } = montar({ definicoes: [DEFINICOES[2]] });

    expect(
      wrapper.find('[data-test-id="bloco-campos-da-conversa"]').exists()
    ).toBe(false);
  });

  it('quem opera grava juntando com os outros campos da conversa', async () => {
    const { wrapper, acoes } = montar();

    wrapper
      .findAllComponents({ name: 'CustomAttribute' })[1]
      .vm.$emit('update', 'modelo_do_carro', 'Onix');
    await flushPromises();

    expect(acoes).toContainEqual([
      'updateCustomAttributes',
      {
        conversationId: 42,
        customAttributes: { placa: 'ABC1D23', modelo_do_carro: 'Onix' },
      },
    ]);
  });

  it('apagar tira só aquele campo', async () => {
    const { wrapper, acoes } = montar();

    wrapper
      .findAllComponents({ name: 'CustomAttribute' })[0]
      .vm.$emit('delete', 'placa');
    await flushPromises();

    expect(acoes).toContainEqual([
      'updateCustomAttributes',
      { conversationId: 42, customAttributes: {} },
    ]);
  });

  it('quem só lê vê o valor, sem editar', async () => {
    const { wrapper, acoes } = montar({ podeOperar: false });
    const campos = wrapper.findAllComponents({ name: 'CustomAttribute' });

    expect(campos.map(campo => campo.props('showActions'))).toEqual([
      false,
      false,
    ]);
    expect(wrapper.text()).toContain('ABC1D23');

    campos[1].vm.$emit('update', 'modelo_do_carro', 'Onix');
    await flushPromises();
    expect(acoes).toEqual([]);
  });

  // A caixa de marcar e a lista não respeitam o show-actions do CustomAttribute:
  // para quem só lê, ficam dentro de um fieldset desabilitado.
  describe('caixa de marcar e lista', () => {
    const DE_ESCOLHA = [
      definicao(4, 'tem_seguro', 'Tem seguro', 'conversation_attribute', {
        attribute_display_type: 'checkbox',
      }),
      definicao(5, 'cor', 'Cor', 'conversation_attribute', {
        attribute_display_type: 'list',
        attribute_values: ['Prata', 'Preto'],
      }),
    ];
    const travados = wrapper =>
      wrapper.findAll('fieldset').map(campo => campo.element.disabled);

    it('quem só lê não consegue marcar nem escolher', () => {
      const { wrapper } = montar({ podeOperar: false, definicoes: DE_ESCOLHA });

      expect(travados(wrapper)).toEqual([true, true]);
      expect(wrapper.find('fieldset input[type="checkbox"]').exists()).toBe(
        true
      );
      expect(wrapper.findAll('fieldset')[1].find('button').exists()).toBe(
        true
      );
    });

    it('quem opera marca e escolhe', () => {
      const { wrapper } = montar({ definicoes: DE_ESCOLHA });

      expect(travados(wrapper)).toEqual([false, false]);
    });
  });
});
