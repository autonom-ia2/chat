import { flushPromises, mount } from '@vue/test-utils';
import CrmCardCustomFields from './CrmCardCustomFields.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';
import ListAttribute from 'dashboard/components-next/CustomAttributes/ListAttribute.vue';
import CheckboxAttribute from 'dashboard/components-next/CustomAttributes/CheckboxAttribute.vue';

const { store, alertSpy, conta, api } = vi.hoisted(() => ({
  store: { getters: {}, dispatch: vi.fn() },
  alertSpy: vi.fn(),
  conta: { memoria: false },
  api: { getMemoriaFatos: vi.fn() },
}));

vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => store,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alertSpy }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { id: 7, timezone: 'America/Sao_Paulo' } },
    isCloudFeatureEnabled: chave => chave === 'memoria_ia' && conta.memoria,
  }),
}));
vi.mock('dashboard/api/crmKanban', () => ({ default: api }));

const definitions = [
  {
    id: 1,
    attributeKey: 'plan',
    attributeDisplayName: 'Plano',
    attributeDisplayType: 'list',
    attributeValues: ['Básico', 'Pro'],
    attributeModel: 'card_attribute',
  },
  {
    id: 2,
    attributeKey: 'seats',
    attributeDisplayName: 'Licenças',
    attributeDisplayType: 'number',
    attributeModel: 'card_attribute',
  },
  {
    id: 3,
    attributeKey: 'signed',
    attributeDisplayName: 'Contrato assinado',
    attributeDisplayType: 'checkbox',
    attributeModel: 'card_attribute',
  },
];

const card = {
  id: 42,
  custom_attributes: { plan: 'Básico', seats: 3, signed: true },
};

const mountFields = (props = {}) =>
  mount(CrmCardCustomFields, {
    props: { card, canManage: true, ...props },
    global: {
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
      directives: { onClickaway: {} },
    },
  });

const setGetters = ({ defs = definitions, role = 'agent' } = {}) => {
  store.getters = {
    'attributes/getCardAttributes': defs,
    getCurrentRole: role,
    getCurrentUser: { accounts: [{ id: 7, permissions: [] }] },
    getCurrentAccountId: 7,
  };
};

describe('CrmCardCustomFields', () => {
  beforeEach(() => {
    store.dispatch = vi.fn().mockResolvedValue({
      id: 42,
      custom_attributes: { plan: 'Pro', seats: 3, signed: true },
    });
    alertSpy.mockClear();
    conta.memoria = false;
    api.getMemoriaFatos.mockReset();
    setGetters();
  });

  it('lists every card definition with the value stored on the card', () => {
    const wrapper = mountFields();

    const rows = wrapper.findAll('[data-field]');
    expect(rows.map(row => row.attributes('data-field'))).toEqual([
      'plan',
      'seats',
      'signed',
    ]);
    expect(wrapper.find('[data-field="plan"]').text()).toContain('Plano');
    expect(wrapper.find('[data-field="plan"]').text()).toContain('Básico');
    expect(wrapper.findComponent(ListAttribute).props('attribute').value).toBe(
      'Básico'
    );
    expect(wrapper.findComponent(OtherAttribute).props('attribute').value).toBe(
      3
    );
    expect(
      wrapper.findComponent(CheckboxAttribute).props('attribute').value
    ).toBe(true);
    expect(store.dispatch).toHaveBeenCalledWith('attributes/get');
  });

  it('saves only the edited key through crmKanban/updateCard', async () => {
    const wrapper = mountFields();

    wrapper.findComponent(ListAttribute).vm.$emit('update', 'Pro');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('crmKanban/updateCard', {
      id: 42,
      custom_attributes: { plan: 'Pro' },
    });
    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.DRAWER.CARD_FIELDS.UPDATE_SUCCESS'
    );
    expect(wrapper.findComponent(ListAttribute).props('attribute').value).toBe(
      'Pro'
    );
  });

  it('sends numbers as numbers and clears a field with null', async () => {
    const wrapper = mountFields();

    wrapper.findComponent(OtherAttribute).vm.$emit('update', '12');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('crmKanban/updateCard', {
      id: 42,
      custom_attributes: { seats: 12 },
    });

    wrapper.findComponent(OtherAttribute).vm.$emit('delete');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('crmKanban/updateCard', {
      id: 42,
      custom_attributes: { seats: null },
    });
  });

  it('warns and keeps the value when the save fails', async () => {
    store.dispatch = vi.fn(action =>
      action === 'crmKanban/updateCard'
        ? Promise.reject(new Error('boom'))
        : Promise.resolve()
    );
    const wrapper = mountFields();

    wrapper.findComponent(ListAttribute).vm.$emit('update', 'Pro');
    await flushPromises();

    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.DRAWER.CARD_FIELDS.UPDATE_ERROR'
    );
    expect(wrapper.findComponent(ListAttribute).props('attribute').value).toBe(
      'Básico'
    );
  });

  it('is read-only without card permission', async () => {
    const wrapper = mountFields({ canManage: false });

    expect(wrapper.findComponent(ListAttribute).exists()).toBe(false);
    expect(wrapper.find('[data-field="plan"]').text()).toContain('Básico');
    expect(wrapper.find('[data-field="signed"]').text()).toContain(
      'CRM_KANBAN.RELATIONSHIP.VALUE_YES'
    );
  });

  it('shows the empty-state hint to admins when no card field exists', () => {
    setGetters({ defs: [], role: 'administrator' });
    const wrapper = mountFields();

    expect(
      wrapper.find('[data-testid="crm-card-custom-fields-empty"]').text()
    ).toContain('CRM_KANBAN.DRAWER.CARD_FIELDS.EMPTY_ADMIN');
    expect(
      wrapper.find('[data-testid="crm-card-custom-fields"]').isVisible()
    ).toBe(true);
  });

  it('hides the section for non-admins when no card field exists', () => {
    setGetters({ defs: [] });
    const wrapper = mountFields();

    expect(
      wrapper.find('[data-testid="crm-card-custom-fields"]').isVisible()
    ).toBe(false);
  });

  describe('origem do valor (#1601, memória das IAs)', () => {
    const fato = extra => ({
      escopo: 'card',
      tipo: 'fato',
      situacao: 'vigente',
      expirado_em: null,
      chave: 'plan',
      valor: 'Básico',
      fonte: 'cliente',
      valido_desde: '2026-10-17T17:02:00Z',
      registrado_em: '2026-10-17T17:03:00Z',
      prova_message_id: 900,
      prova_conversation_display_id: 31,
      ...extra,
    });

    it('sem a flag não busca nem mostra nada', async () => {
      const wrapper = mountFields();
      await flushPromises();

      expect(api.getMemoriaFatos).not.toHaveBeenCalled();
      expect(
        wrapper.find('[data-testid="crm-card-field-origem"]').exists()
      ).toBe(false);
    });

    it('mostra "cliente informou" com a hora no fuso da conta e o link para a mensagem', async () => {
      conta.memoria = true;
      api.getMemoriaFatos.mockResolvedValue({ data: { payload: [fato()] } });
      const wrapper = mountFields();
      await flushPromises();

      const linha = wrapper.find(
        '[data-field="plan"] [data-testid="crm-card-field-origem"]'
      );
      expect(linha.text()).toContain(
        'CRM_KANBAN.DRAWER.CARD_FIELDS.ORIGEM.CLIENTE'
      );
      const destino = JSON.parse(linha.find('a').attributes('data-to'));
      expect(destino).toEqual({
        name: 'inbox_conversation',
        params: { accountId: '7', conversation_id: 31 },
        query: { messageId: 900 },
      });
    });

    it('corrigido pela pessoa: sem link; valor diferente do campo não ganha origem', async () => {
      conta.memoria = true;
      api.getMemoriaFatos.mockResolvedValue({
        data: {
          payload: [
            fato({
              fonte: 'pessoa_corrigiu',
              corrigido_por_nome: 'Ana',
              prova_message_id: null,
            }),
            fato({ chave: 'seats', valor: '99' }),
          ],
        },
      });
      const wrapper = mountFields();
      await flushPromises();

      const linha = wrapper.find(
        '[data-field="plan"] [data-testid="crm-card-field-origem"]'
      );
      expect(linha.text()).toContain(
        'CRM_KANBAN.DRAWER.CARD_FIELDS.ORIGEM.CORRIGIDO'
      );
      expect(linha.find('a').exists()).toBe(false);
      expect(
        wrapper
          .find('[data-field="seats"] [data-testid="crm-card-field-origem"]')
          .exists()
      ).toBe(false);
    });
  });
});
