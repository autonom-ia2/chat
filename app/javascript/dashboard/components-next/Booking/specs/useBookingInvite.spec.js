import { defineComponent, nextTick, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useBookingInvite } from '../useBookingInvite';
import BookingInvitesAPI from 'dashboard/api/crmBookingInvites';

// A lógica do link de agenda (#1190) que o botão da conversa e a tela "Link da
// agenda" do card do funil (#1423) dividem.
const router = { hasRoute: vi.fn(() => true), push: vi.fn() };
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getCurrentAccountId: 1,
      getCurrentRole: 'agent',
      getCurrentUser: { accounts: [{ id: 1, permissions: [] }] },
    },
  }),
}));
vi.mock('vue-router', () => ({ useRouter: () => router }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('../useBookingInviteAvailable', async () => {
  const { computed } = await import('vue');
  return { useBookingInviteAvailable: () => computed(() => true) };
});
vi.mock('dashboard/api/crmBookingInvites', () => ({
  default: {
    index: vi.fn(),
    create: vi.fn(),
    deliver: vi.fn(),
    copied: vi.fn(),
    cancel: vi.fn(),
  },
}));

const convite = (extra = {}) => ({
  id: 5,
  url: 'https://x.test/b/abc',
  text: 'Oi! https://x.test/b/abc',
  state: 'created',
  expires_at: '2099-10-16T12:00:00Z',
  booking_page: { id: 3, title: 'Conversa' },
  ...extra,
});

const usar = card => {
  let link;
  mount(
    defineComponent({
      setup() {
        link = useBookingInvite({
          conversation: ref(null),
          card,
          withStatus: ref(true),
        });
        return () => null;
      },
    })
  );
  return link;
};

describe('useBookingInvite', () => {
  afterEach(() => vi.clearAllMocks());

  it('reaproveita o link ativo e não cria outro', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { pages: [{ id: 3 }], payload: [convite()] },
    });
    const link = usar(ref({ id: 7 }));
    await link.prepareInvite();
    expect(BookingInvitesAPI.create).not.toHaveBeenCalled();
    expect(link.text.value).toBe('Oi! https://x.test/b/abc');
    expect(link.textHasLink.value).toBe(true);
  });

  it('sem página publicada, diz que falta a página', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { pages: [], payload: [] },
    });
    const link = usar(ref({ id: 7 }));
    await link.prepareInvite();
    expect(link.hasNoPage.value).toBe(true);
    expect(link.showSettingsShortcut.value).toBe(false);
  });

  it('servidor com o link desligado marca isDisabledOnServer', async () => {
    BookingInvitesAPI.index.mockRejectedValue({
      response: { status: 404, data: { error: 'crm.booking_v2.disabled' } },
    });
    const link = usar(ref({ id: 7 }));
    await flushPromises();
    expect(link.isDisabledOnServer.value).toBe(true);
    expect(link.isEnabled.value).toBe(false);
  });

  it('cancelar marca o link como cancelado e oferece outro', async () => {
    BookingInvitesAPI.index.mockResolvedValue({
      data: { pages: [{ id: 3 }], payload: [convite()] },
    });
    BookingInvitesAPI.cancel.mockResolvedValue({});
    const link = usar(ref({ id: 7 }));
    await link.prepareInvite();
    await link.cancelLink();
    expect(link.isInviteActive.value).toBe(false);
  });

  it('descarta a resposta de outro card (troca rápida)', async () => {
    let responder;
    BookingInvitesAPI.index.mockReturnValueOnce(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    BookingInvitesAPI.index.mockResolvedValue({
      data: { pages: [], payload: [] },
    });
    const card = ref({ id: 7 });
    const link = usar(card);
    card.value = { id: 8 };
    await nextTick();
    await flushPromises();
    responder({
      data: { pages: [{ id: 3 }], payload: [convite({ state: 'sent' })] },
    });
    await flushPromises();
    expect(link.badgeState.value).toBe('');
  });
});
