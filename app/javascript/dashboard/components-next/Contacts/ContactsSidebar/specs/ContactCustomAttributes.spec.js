import { mount } from '@vue/test-utils';
import ContactCustomAttributes from '../ContactCustomAttributes.vue';

// #2138 — na página do contato, os campos internos da WAHA não aparecem, nem nos
// usados (com valor) nem nos sem valor; os campos de verdade continuam. A lista
// passa pelo getter de verdade (attributes/getContactAttributes), que os esconde.
const state = vi.hoisted(() => ({ contactAttributes: [] }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', async () => {
  const { getters } = await import('dashboard/store/modules/attributes');
  return {
    useMapGetter: () => ({
      get value() {
        return getters.getContactAttributes({
          records: state.contactAttributes,
        });
      },
    }),
  };
});
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: { value: {} } }),
}));

const definicao = (id, chave) => ({
  id,
  attribute_key: chave,
  attribute_display_name: chave,
  attribute_display_type: 'text',
  attribute_model: 'contact_attribute',
});

const montar = customAttributes =>
  mount(ContactCustomAttributes, {
    props: { selectedContact: { id: 9, customAttributes } },
    global: {
      stubs: {
        ContactCustomAttributeItem: {
          props: ['attribute'],
          template: '<div data-campo>{{ attribute.attributeKey }}</div>',
        },
      },
    },
  });
const campos = wrapper => wrapper.findAll('[data-campo]').map(c => c.text());

describe('ContactCustomAttributes — campos internos da WAHA', () => {
  beforeEach(() => {
    state.contactAttributes = [
      definicao(1, 'melhor_horario'),
      definicao(2, 'waha_whatsapp_chat_id'),
      definicao(3, 'waha_whatsapp_jid'),
      definicao(4, 'waha_whatsapp_lid'),
      definicao(5, 'aniversario'),
    ];
  });

  it('com valor: só os campos de verdade aparecem', () => {
    const wrapper = montar({
      melhor_horario: 'Depois das 14h',
      waha_whatsapp_chat_id: '5511900000000@c.us',
      waha_whatsapp_lid: '123@lid',
    });
    expect(campos(wrapper)).toEqual(['melhor_horario', 'aniversario']);
  });

  it('sem valor: os internos também não aparecem entre os campos vazios', () => {
    const wrapper = montar({});
    expect(campos(wrapper)).toEqual(['melhor_horario', 'aniversario']);
  });

  it('só com os internos definidos, a página mostra o estado vazio', () => {
    state.contactAttributes = [definicao(2, 'waha_whatsapp_chat_id')];
    const wrapper = montar({ waha_whatsapp_chat_id: 'x@c.us' });
    expect(campos(wrapper)).toEqual([]);
    expect(wrapper.text()).toContain(
      'CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.EMPTY_STATE'
    );
  });
});
