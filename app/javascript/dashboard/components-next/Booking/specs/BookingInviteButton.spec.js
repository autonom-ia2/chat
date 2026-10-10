import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../vitest.i18n';
import BookingInviteButton from '../BookingInviteButton.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BookingInvitesAPI from 'dashboard/api/crmBookingInvites';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';

withFullI18n('pt_BR');

const store = { getters: {} };
const router = { hasRoute: vi.fn(() => true), push: vi.fn() };

vi.mock('vuex', () => ({ useStore: () => store }));
vi.mock('vue-router', () => ({ useRouter: () => router }));
// A régua real de quem vê o CRM (useCrmPermissions) lendo os getters deste store de teste.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStoreGetters: () =>
      Object.fromEntries(
        Object.keys(store.getters).map(key => [
          key,
          computed(() => store.getters[key]),
        ])
      ),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(() => Promise.resolve()),
}));
vi.mock('dashboard/api/crmBookingInvites', () => ({
  default: {
    index: vi.fn(),
    create: vi.fn(),
    deliver: vi.fn(),
    cancel: vi.fn(),
  },
}));

const URL = 'https://chat.exemplo.com/b/Xk4p9Q';
const invite = (overrides = {}) => ({
  id: 5,
  code: 'Xk4p9Q',
  url: URL,
  text: `Oi, Marcos! Escolha o melhor horário por aqui: ${URL}`,
  expires_at: '2026-10-16T12:00:00Z',
  state: 'created',
  booking_page: { id: 3, title: 'Conversa de 30 min' },
  contact: { id: 9, name: 'Marcos' },
  ...overrides,
});
const page = { id: 3, title: 'Conversa de 30 min' };
const httpError = (status, error) => ({
  response: { status, data: { error } },
});
// Sem resposta do servidor (queda de rede): o axios rejeita sem `response`.
const networkError = () => new Error('Network Error');

const setStore = ({
  flag = true,
  role = 'administrator',
  permissions = [],
  customRoleId = null,
}) => {
  store.getters = {
    getCurrentAccountId: 1,
    getCurrentRole: role,
    getCurrentCustomRoleId: customRoleId,
    getCurrentUser: {
      accounts: [{ id: 1, permissions, custom_role_id: customRoleId }],
    },
    'accounts/isFeatureEnabledonAccount': (_id, name) =>
      flag && name === 'crm_booking_v2',
  };
};

const mountButton = (props = { conversation: { id: 12 } }) =>
  mount(BookingInviteButton, {
    props,
    attachTo: document.body,
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        ChoiceSelect: {
          props: ['modelValue', 'options'],
          emits: ['update:modelValue', 'change'],
          template:
            '<button type="button" role="combobox" data-choice @click="$emit(\'update:modelValue\', 4); $emit(\'change\')" />',
        },
      },
    },
  });

const openPanel = async wrapper => {
  await wrapper.get('[data-booking-invite-trigger]').trigger('click');
  await flushPromises();
};

// O segundo diálogo é a confirmação de "Cancelar link".
const cancelConfirm = wrapper => wrapper.findAllComponents(Dialog).at(1);

describe('BookingInviteButton', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    setStore({});
    BookingInvitesAPI.index.mockResolvedValue({
      data: { payload: [], pages: [page] },
    });
    BookingInvitesAPI.create.mockResolvedValue({
      data: { payload: invite() },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
    document.body.innerHTML = '';
  });

  it('stays hidden without the account flag', () => {
    setStore({ flag: false });
    const wrapper = mountButton();
    expect(wrapper.find('[data-booking-invite-trigger]').exists()).toBe(false);
  });

  it('stays hidden when the meetings calendar is off', () => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'false' };
    const wrapper = mountButton();
    expect(wrapper.find('[data-booking-invite-trigger]').exists()).toBe(false);
  });

  it('creates the invite and shows the ready text with the link', async () => {
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(BookingInvitesAPI.index).toHaveBeenCalledWith({
      conversation_id: 12,
    });
    expect(BookingInvitesAPI.create).toHaveBeenCalledWith({
      bookingPageId: 3,
      cardId: undefined,
      conversationId: 12,
    });
    expect(wrapper.text()).toContain('Link de agenda para Marcos');
    expect(wrapper.text()).toContain('Vale até 16/10');
    expect(wrapper.text()).toContain('Página: Conversa de 30 min');
    expect(wrapper.get('[data-booking-invite-text]').element.value).toContain(
      URL
    );
    expect(wrapper.find('[data-choice]').exists()).toBe(false);
  });

  it('reuses the latest active invite instead of creating another', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { payload: [invite({ state: 'opened' })], pages: [page] },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(BookingInvitesAPI.create).not.toHaveBeenCalled();
    expect(wrapper.get('[data-booking-invite-state]').text()).toBe('Aberto');
  });

  it('offers the page choice only with more than one page', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: {
        payload: [],
        pages: [page, { id: 4, title: 'Avaliação' }],
      },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    await wrapper.get('[data-choice]').trigger('click');
    await flushPromises();
    expect(BookingInvitesAPI.create).toHaveBeenLastCalledWith(
      expect.objectContaining({ bookingPageId: 4 })
    );
  });

  it('copies only the link', async () => {
    const wrapper = mountButton();
    await openPanel(wrapper);
    await wrapper.get('[data-booking-copy]').trigger('click');
    await flushPromises();

    expect(copyTextToClipboard).toHaveBeenCalledWith(URL);
    expect(useAlert).toHaveBeenCalledWith('Link copiado. Cole onde quiser.');
  });

  it('sends the edited text in the conversation', async () => {
    BookingInvitesAPI.deliver.mockResolvedValue({
      data: { payload: invite({ state: 'sent', sent_at: '2026-10-09' }) },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);
    const edited = `Marcos, marque aqui: ${URL}`;
    await wrapper.get('[data-booking-invite-text]').setValue(edited);
    await wrapper.get('[data-booking-send]').trigger('click');
    await flushPromises();

    expect(BookingInvitesAPI.deliver).toHaveBeenCalledWith(5, {
      conversationId: 12,
      text: edited,
    });
    expect(useAlert).toHaveBeenCalledWith('Mensagem enviada na conversa.');
  });

  it('blocks sending when the text lost the link', async () => {
    const wrapper = mountButton();
    await openPanel(wrapper);
    await wrapper.get('[data-booking-invite-text]').setValue('Oi, Marcos!');

    expect(
      wrapper.get('[data-booking-send]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain('O texto precisa ter o link.');
  });

  it('hides "send" on a card without conversation, keeping copy', async () => {
    const wrapper = mountButton({ card: { id: 7, contact: { name: 'Ana' } } });
    await openPanel(wrapper);

    expect(BookingInvitesAPI.index).toHaveBeenCalledWith({ card_id: 7 });
    expect(wrapper.find('[data-booking-send]').exists()).toBe(false);
    expect(wrapper.find('[data-booking-copy]').exists()).toBe(true);
  });

  it('uses the display number of the card conversation, not its database id', async () => {
    const card = {
      id: 7,
      conversation_id: 9001,
      conversation: { id: 9001, display_id: 42 },
    };
    const wrapper = mountButton({ card });
    await openPanel(wrapper);

    expect(BookingInvitesAPI.create).toHaveBeenCalledWith({
      bookingPageId: 3,
      cardId: 7,
      conversationId: 42,
    });
    await wrapper.get('[data-booking-send]').trigger('click');
    expect(BookingInvitesAPI.deliver).toHaveBeenCalledWith(
      5,
      expect.objectContaining({ conversationId: 42 })
    );
  });

  it('shows the settings shortcut to admins when there is no page', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { payload: [], pages: [] },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(wrapper.text()).toContain('Publique uma página de agendamento');
    await wrapper.get('[data-booking-open-settings]').trigger('click');
    expect(router.push).toHaveBeenCalledWith({
      name: 'settings_booking',
      params: { accountId: 1 },
    });
  });

  it('shows the "ask the admin" sentence to agents on 422 no_page', async () => {
    setStore({ role: 'agent' });
    BookingInvitesAPI.create.mockRejectedValue(
      httpError(422, 'crm.booking_v2.no_page')
    );
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(wrapper.text()).toContain(
      'Peça ao administrador para publicar uma página de agendamento.'
    );
    expect(wrapper.find('[data-booking-open-settings]').exists()).toBe(false);
  });

  it('shows the shortcut to a custom role with agendamento_manage', async () => {
    setStore({ role: 'agent', permissions: ['agendamento_manage'] });
    BookingInvitesAPI.index.mockResolvedValue({
      data: { payload: [], pages: [] },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(wrapper.find('[data-booking-open-settings]').exists()).toBe(true);
  });

  it('hides itself when the server says the flag is off', async () => {
    BookingInvitesAPI.index.mockRejectedValue(
      httpError(404, 'crm.booking_v2.disabled')
    );
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(wrapper.find('[data-booking-invite-trigger]').exists()).toBe(false);
  });

  it('asks before canceling and "Back" keeps the link', async () => {
    const wrapper = mountButton();
    await openPanel(wrapper);
    const showModal = vi.mocked(HTMLDialogElement.prototype.showModal);
    showModal.mockClear();
    await wrapper.get('[data-booking-cancel]').trigger('click');

    expect(showModal).toHaveBeenCalledTimes(1);
    const confirm = cancelConfirm(wrapper);
    expect(confirm.text()).toContain('Cancelar o link?');
    expect(confirm.text()).toContain(
      'O cliente não vai mais conseguir marcar por ele.'
    );
    // Neste ambiente o Button do diálogo vira <button> nativo com o rótulo no atributo `label`.
    expect(confirm.find('button[label="Sim, cancelar"]').exists()).toBe(true);
    await confirm.get('button[label="Voltar"]').trigger('click');
    await flushPromises();

    expect(BookingInvitesAPI.cancel).not.toHaveBeenCalled();
    expect(wrapper.find('[data-booking-copy]').exists()).toBe(true);
  });

  it('cancels the link after confirming and offers a new one', async () => {
    BookingInvitesAPI.cancel.mockResolvedValue({});
    const wrapper = mountButton();
    await openPanel(wrapper);
    await wrapper.get('[data-booking-cancel]').trigger('click');
    await cancelConfirm(wrapper).get('form').trigger('submit');
    await flushPromises();

    expect(BookingInvitesAPI.cancel).toHaveBeenCalledWith(5);
    expect(wrapper.get('[data-booking-invite-state]').text()).toBe('Cancelado');
    expect(wrapper.find('[data-booking-new]').exists()).toBe(true);
    expect(wrapper.find('[data-booking-copy]').exists()).toBe(false);
  });

  it.each([
    ['sent', 'Enviado'],
    ['opened', 'Aberto'],
    ['scheduled', 'Agendado'],
  ])('shows the %s badge on the card without opening', async (state, text) => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { payload: [invite({ state })], pages: [page] },
    });
    const wrapper = mountButton({ card: { id: 7 }, showStatus: true });
    await flushPromises();

    expect(wrapper.get('[data-booking-invite-badge]').text()).toBe(text);
  });

  it('shows no badge for a link that was never sent', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { payload: [invite()], pages: [page] },
    });
    const wrapper = mountButton({ card: { id: 7 }, showStatus: true });
    await flushPromises();

    expect(wrapper.find('[data-booking-invite-badge]').exists()).toBe(false);
  });

  it.each([
    ['expired', 'Venceu'],
    ['canceled', 'Cancelado'],
  ])('translates the %s state inside the panel', async (state, text) => {
    BookingInvitesAPI.create.mockResolvedValue({
      data: { payload: invite({ state }) },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(wrapper.get('[data-booking-invite-state]').text()).toBe(text);
  });

  it('stays hidden for a custom role without crm_view or crm_admin', () => {
    setStore({
      role: 'agent',
      customRoleId: 8,
      permissions: ['agendamento_manage', 'conversation_manage', 'custom_role'],
    });
    const wrapper = mountButton();
    expect(wrapper.find('[data-booking-invite-trigger]').exists()).toBe(false);
  });

  it.each([['crm_view'], ['crm_admin']])(
    'shows for a custom role with %s',
    key => {
      setStore({
        role: 'agent',
        customRoleId: 8,
        permissions: [key, 'custom_role'],
      });
      const wrapper = mountButton();
      expect(wrapper.find('[data-booking-invite-trigger]').exists()).toBe(true);
    }
  );

  it('says the person has no access when the API answers 401', async () => {
    BookingInvitesAPI.index.mockRejectedValue(httpError(401, 'Unauthorized'));
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(useAlert).toHaveBeenCalledWith('Você não tem acesso a isto.');
  });

  it('asks to copy the link when the client must message first', async () => {
    BookingInvitesAPI.deliver.mockRejectedValue(
      httpError(422, 'crm.booking_v2.cannot_reply')
    );
    const wrapper = mountButton();
    await openPanel(wrapper);
    await wrapper.get('[data-booking-send]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'O cliente precisa mandar mensagem primeiro. Copie o link e envie de outro jeito.'
    );
    expect(wrapper.find('[data-booking-copy]').exists()).toBe(true);
  });

  it('shows the load error when the network fails on opening', async () => {
    BookingInvitesAPI.index.mockRejectedValue(networkError());
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(useAlert).toHaveBeenCalledWith(
      'Não foi possível abrir o link agora. Tente de novo.'
    );
    expect(wrapper.find('[data-booking-invite-trigger]').exists()).toBe(true);
  });

  it('shows the send error when the network fails on sending', async () => {
    BookingInvitesAPI.deliver.mockRejectedValue(networkError());
    const wrapper = mountButton();
    await openPanel(wrapper);
    await wrapper.get('[data-booking-send]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não foi possível enviar. Confira se o texto tem o link e se o cliente pode receber mensagem.'
    );
  });

  it('shows the copy error when the clipboard fails', async () => {
    copyTextToClipboard.mockRejectedValueOnce(networkError());
    const wrapper = mountButton();
    await openPanel(wrapper);
    await wrapper.get('[data-booking-copy]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Não foi possível copiar o link.');
  });

  it('does not reuse an active invite whose link no longer works', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: {
        payload: [invite({ state: 'sent', usable: false })],
        pages: [page],
      },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(BookingInvitesAPI.create).toHaveBeenCalled();
  });

  it('treats an unusable link as expired: no send, no copy, only a new link', async () => {
    BookingInvitesAPI.create.mockResolvedValue({
      data: { payload: invite({ state: 'sent', usable: false }) },
    });
    const wrapper = mountButton();
    await openPanel(wrapper);

    expect(wrapper.get('[data-booking-invite-state]').text()).toBe('Venceu');
    expect(wrapper.find('[data-booking-send]').exists()).toBe(false);
    expect(wrapper.find('[data-booking-copy]').exists()).toBe(false);
    expect(wrapper.find('[data-booking-new]').exists()).toBe(true);
  });

  it('never renders a native <select>', async () => {
    const source = readFileSync(
      resolve(__dirname, '../BookingInviteButton.vue'),
      'utf8'
    );
    expect(source.includes('<select')).toBe(false);

    const wrapper = mountButton();
    await openPanel(wrapper);
    expect(document.body.querySelector('select')).toBeNull();
  });
});
