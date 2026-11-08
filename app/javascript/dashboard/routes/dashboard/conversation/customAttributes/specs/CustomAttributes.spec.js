import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { getters as gettersDosCampos } from 'dashboard/store/modules/attributes';
import CustomAttributes from '../CustomAttributes.vue';

// #2138 — os atributos internos da WAHA (chat id do WhatsApp) não aparecem na
// lista de campos do contato. Quem os esconde é o getter do store (aqui o de
// verdade); o lado do Relacionamentos está no spec do useRelationships.
const relacionamentos = vi.hoisted(() => ({ ligado: false, definicoes: [] }));
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({
    attributesEnabled: ref(relacionamentos.ligado),
    state: ref({
      definitions: relacionamentos.definicoes,
      configuration: { surfaces: { contact_sidebar: { mode: 'legacy' } } },
      error: false,
    }),
    accountId: ref(1),
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: ref({}), updateUISettings: vi.fn() }),
}));
vi.mock('vue-router', () => ({ useRoute: () => ({ params: {} }) }));

const DEFINICOES = [
  'melhor_horario',
  'waha_whatsapp_chat_id',
  'waha_whatsapp_jid',
  'waha_whatsapp_lid',
  'cpf',
].map((chave, indice) => ({
  id: indice + 1,
  attribute_key: chave,
  attribute_display_name: chave,
  attribute_display_type: 'text',
  attribute_model: 'contact_attribute',
}));

const VALORES = {
  melhor_horario: 'Depois das 14h',
  waha_whatsapp_chat_id: '5511900000001@c.us',
  waha_whatsapp_jid: '5511900000001@c.us',
  waha_whatsapp_lid: '123@lid',
  cpf: '000',
};

const montar = attributeFrom => {
  const store = createStore({
    getters: {
      getSelectedChat: () => ({ id: 42, meta: { sender: { id: 9 } } }),
      'contacts/getContact': () => () => ({
        id: 9,
        custom_attributes: VALORES,
      }),
      'attributes/getAttributesByModel': () =>
        gettersDosCampos.getAttributesByModel({ records: DEFINICOES }),
      canOperateConversation: () => () => true,
      getCurrentRole: () => 'agent',
      getCurrentCustomRoleId: () => null,
      getCurrentUser: () => ({ id: 7, accounts: [] }),
      getCurrentAccountId: () => 1,
    },
  });
  return mount(CustomAttributes, {
    props: {
      attributeType: 'contact_attribute',
      attributeFrom,
      contactId: 9,
    },
    global: {
      plugins: [store],
      stubs: {
        CustomAttribute: {
          props: ['attributeKey'],
          template: '<div data-campo>{{ attributeKey }}</div>',
        },
        FieldEditor: {
          props: ['definition'],
          template: '<div data-campo>{{ definition.attribute_key }}</div>',
        },
        FieldConfigurator: true,
        NextButton: true,
      },
    },
  });
};
const campos = wrapper => wrapper.findAll('[data-campo]').map(c => c.text());

describe('CustomAttributes — campos internos do WhatsApp', () => {
  it('não mostra as três chaves waha_whatsapp_*, e mostra o resto na mesma ordem', () => {
    relacionamentos.ligado = false;
    const wrapper = montar('contact_panel');
    expect(campos(wrapper)).toEqual(['melhor_horario', 'cpf']);
  });
});
