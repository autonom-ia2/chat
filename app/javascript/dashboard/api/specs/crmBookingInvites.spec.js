import crmBookingInvites from '../crmBookingInvites';
import ApiClient from '../ApiClient';

describe('#CrmBookingInvitesAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };
  const baseUrl = '/api/v1/accounts/85/crm/booking_invites';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/crm/kanban');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('creates correct instance', () => {
    expect(crmBookingInvites).toBeInstanceOf(ApiClient);
  });

  it('lists the latest invites of a card', () => {
    crmBookingInvites.index({ card_id: 7 });

    expect(axiosMock.get).toHaveBeenCalledWith(baseUrl, {
      params: { card_id: 7 },
    });
  });

  it('creates an invite for the client in snake_case', () => {
    crmBookingInvites.create({
      bookingPageId: 3,
      cardId: 7,
      conversationId: 12,
    });

    expect(axiosMock.post).toHaveBeenCalledWith(baseUrl, {
      booking_page_id: 3,
      card_id: 7,
      conversation_id: 12,
      contact_id: undefined,
    });
  });

  it('delivers the invite in the conversation with the edited text', () => {
    crmBookingInvites.deliver(5, { conversationId: 12, text: 'Oi! link' });

    expect(axiosMock.post).toHaveBeenCalledWith(`${baseUrl}/5/deliver`, {
      conversation_id: 12,
      text: 'Oi! link',
    });
  });

  it('cancels an invite', () => {
    crmBookingInvites.cancel(5);

    expect(axiosMock.delete).toHaveBeenCalledWith(`${baseUrl}/5`);
  });
});
