import { mount, flushPromises } from '@vue/test-utils';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmMeetingDayActions from './CrmMeetingDayActions.vue';

// O dia da reunião no detalhe e no card (#1193, J4-A1/A2/A5/A6/A7): número,
// "Chamar no WhatsApp", "Lembrar", link para remarcar e mover o card. Nada é
// enviado sem o toque do agente.
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/api/crmMeetings', () => ({
  default: { remind: vi.fn(), rebookLink: vi.fn() },
}));
vi.mock('dashboard/api/crmKanban', () => ({ default: { moveCard: vi.fn() } }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));

const DAY = 'CRM_KANBAN.CALENDAR.MEETING_DAY';
const FUTURE = new Date(Date.now() + 86400000).toISOString();

const meeting = (extra = {}) => ({
  id: 7,
  card_id: 30,
  booking: true,
  status: 'scheduled',
  starts_at: FUTURE,
  location_type: 'whatsapp_video',
  confirmation_status: 'pending',
  notices_stopped: false,
  outcome: null,
  client: {
    name: 'Marcos Lima',
    phone: '+5511912345678',
    whatsapp_url: 'https://wa.me/5511912345678',
    conversation_id: null,
  },
  ...extra,
});

const mountActions = (props = {}) =>
  mount(CrmMeetingDayActions, {
    props: { meeting: meeting(), accountId: 1, ...props },
  });

const find = (wrapper, test) => wrapper.find(`[data-test="${test}"]`);
const refusal = (key, url) => ({
  response: { data: { error: `crm.booking_v2.${key}`, url } },
});

describe('CrmMeetingDayActions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  afterEach(() => vi.restoreAllMocks());

  describe('number and call (J4-A1/A2)', () => {
    it('shows the client number and opens wa.me when there is no conversation to open, explaining the video call', async () => {
      const wrapper = mountActions();

      expect(find(wrapper, 'meeting-client-phone').text()).toContain(
        '+55 11 91234 5678'
      );
      expect(find(wrapper, 'meeting-call').text()).toContain(
        `${DAY}.CALL_HINT`
      );
      await find(wrapper, 'meeting-call-button').trigger('click');

      expect(window.open).toHaveBeenCalledWith(
        'https://wa.me/5511912345678',
        '_blank',
        'noopener,noreferrer'
      );
      expect(push).not.toHaveBeenCalled();
    });

    it('opens the existing WhatsApp conversation in the panel when there is one', async () => {
      const wrapper = mountActions({
        meeting: meeting({
          location_type: 'whatsapp_voice',
          client: { ...meeting().client, conversation_id: 42 },
        }),
      });

      expect(find(wrapper, 'meeting-call').text()).toContain(
        `${DAY}.CALL_HINT_VOICE`
      );
      await find(wrapper, 'meeting-call-button').trigger('click');

      expect(push).toHaveBeenCalledWith({
        name: 'inbox_conversation',
        params: { accountId: 1, conversation_id: 42 },
      });
      expect(window.open).not.toHaveBeenCalled();
    });

    it('has no call button for an in-person meeting nor after it was canceled', () => {
      expect(
        find(
          mountActions({ meeting: meeting({ location_type: 'in_person' }) }),
          'meeting-call'
        ).exists()
      ).toBe(false);
      expect(
        find(
          mountActions({ meeting: meeting({ status: 'canceled' }) }),
          'meeting-call'
        ).exists()
      ).toBe(false);
    });
  });

  describe('"Lembrar" (J4-A5)', () => {
    it('sends only on tap, then shows it was sent and tells the parent', async () => {
      crmMeetingsAPI.remind.mockResolvedValue({
        data: { payload: { reminded_at: 'x', message_id: 3 } },
      });
      const wrapper = mountActions();
      expect(crmMeetingsAPI.remind).not.toHaveBeenCalled();

      await find(wrapper, 'meeting-remind-button').trigger('click');
      await flushPromises();

      expect(crmMeetingsAPI.remind).toHaveBeenCalledWith(1, '7');
      const button = find(wrapper, 'meeting-remind-button');
      expect(button.text()).toContain(`${DAY}.REMIND_SENT`);
      expect(button.attributes('disabled')).toBeDefined();
      expect(wrapper.emitted('changed')).toHaveLength(1);
    });

    it('explains a closed window in lay words and offers to copy the link', async () => {
      crmMeetingsAPI.remind.mockRejectedValue(
        refusal('cannot_reply', 'https://app/b/AB3K9QXZ')
      );
      const wrapper = mountActions();

      await find(wrapper, 'meeting-remind-button').trigger('click');
      await flushPromises();

      const box = find(wrapper, 'meeting-day-refusal');
      expect(box.attributes('data-refusal')).toBe('CANNOT_REPLY');
      expect(box.text()).toContain(`${DAY}.REFUSED.CANNOT_REPLY`);
      await find(wrapper, 'meeting-day-copy').trigger('click');
      expect(copyTextToClipboard).toHaveBeenCalledWith(
        'https://app/b/AB3K9QXZ'
      );
      expect(wrapper.emitted('changed')).toBeUndefined();
    });

    it('explains the stop request without offering the link', async () => {
      crmMeetingsAPI.remind.mockRejectedValue(refusal('stopped'));
      const wrapper = mountActions();

      await find(wrapper, 'meeting-remind-button').trigger('click');
      await flushPromises();

      expect(
        find(wrapper, 'meeting-day-refusal').attributes('data-refusal')
      ).toBe('STOPPED');
      expect(find(wrapper, 'meeting-day-copy').exists()).toBe(false);
    });

    it('is not offered when the client confirmed or stopped the notices', () => {
      [
        meeting({ confirmation_status: 'confirmed' }),
        meeting({ notices_stopped: true }),
        meeting({ booking: false }),
      ].forEach(item => {
        expect(
          find(mountActions({ meeting: item }), 'meeting-remind').exists()
        ).toBe(false);
      });
    });
  });

  describe('link to pick another time (J4-A6)', () => {
    const noShow = () => meeting({ outcome: 'no_show' });

    it('asks first and sends the link only on tap', async () => {
      crmMeetingsAPI.rebookLink.mockResolvedValue({
        data: { payload: { id: 5 } },
      });
      const wrapper = mountActions({ meeting: noShow() });

      expect(find(wrapper, 'meeting-rebook').text()).toContain(
        `${DAY}.REBOOK_TITLE {"name":"Marcos"}`
      );
      expect(crmMeetingsAPI.rebookLink).not.toHaveBeenCalled();
      await find(wrapper, 'meeting-rebook-send').trigger('click');
      await flushPromises();

      expect(crmMeetingsAPI.rebookLink).toHaveBeenCalledWith(1, '7');
      expect(find(wrapper, 'meeting-rebook').text()).toContain(
        `${DAY}.REBOOK_SENT`
      );
      expect(wrapper.emitted('changed')).toHaveLength(1);
    });

    it('"Agora não" closes the question without sending anything', async () => {
      const wrapper = mountActions({ meeting: noShow() });

      await find(wrapper, 'meeting-rebook-dismiss').trigger('click');

      expect(find(wrapper, 'meeting-rebook').exists()).toBe(false);
      expect(crmMeetingsAPI.rebookLink).not.toHaveBeenCalled();
    });

    it('shows the refusal with the new link to copy when the window is closed', async () => {
      crmMeetingsAPI.rebookLink.mockRejectedValue(
        refusal('cannot_reply', 'https://app/b/NEW')
      );
      const wrapper = mountActions({ meeting: noShow() });

      await find(wrapper, 'meeting-rebook-send').trigger('click');
      await flushPromises();

      await find(wrapper, 'meeting-day-copy').trigger('click');
      expect(copyTextToClipboard).toHaveBeenCalledWith('https://app/b/NEW');
    });

    it('is not offered before the no-show nor outside booking meetings', () => {
      expect(find(mountActions(), 'meeting-rebook').exists()).toBe(false);
      expect(
        find(
          mountActions({
            meeting: meeting({ outcome: 'no_show', booking: false }),
          }),
          'meeting-rebook'
        ).exists()
      ).toBe(false);
    });
  });

  describe('after "Aconteceu" (J4-A7)', () => {
    const stage = { id: 9, name: 'Proposta', pipeline_id: 2 };

    it('ask mode: "Mover" moves the card through the move route', async () => {
      CrmKanbanAPI.moveCard.mockResolvedValue({});
      const wrapper = mountActions({
        meeting: meeting({ outcome: 'held' }),
        postMeeting: { mode: 'ask', moved: false, stage },
      });

      expect(find(wrapper, 'meeting-post-move').text()).toContain(
        `${DAY}.MOVE_QUESTION {"stage":"Proposta"}`
      );
      await find(wrapper, 'meeting-post-move-confirm').trigger('click');
      await flushPromises();

      expect(CrmKanbanAPI.moveCard).toHaveBeenCalledWith(30, 9);
      expect(find(wrapper, 'meeting-post-move').text()).toContain(
        `${DAY}.MOVED {"stage":"Proposta"}`
      );
      expect(wrapper.emitted('changed')).toHaveLength(1);
    });

    it('ask mode: "Agora não" leaves the card where it is', async () => {
      const wrapper = mountActions({
        postMeeting: { mode: 'ask', moved: false, stage },
      });

      await find(wrapper, 'meeting-post-move-dismiss').trigger('click');

      expect(find(wrapper, 'meeting-post-move').exists()).toBe(false);
      expect(CrmKanbanAPI.moveCard).not.toHaveBeenCalled();
    });

    it('auto mode: only tells where the card went', () => {
      const wrapper = mountActions({
        postMeeting: { mode: 'auto', moved: true, stage },
      });

      expect(find(wrapper, 'meeting-post-move').text()).toContain(
        `${DAY}.MOVED {"stage":"Proposta"}`
      );
      expect(find(wrapper, 'meeting-post-move-confirm').exists()).toBe(false);
      expect(CrmKanbanAPI.moveCard).not.toHaveBeenCalled();
    });

    it('shows a lay error when moving fails', async () => {
      CrmKanbanAPI.moveCard.mockRejectedValue(new Error('x'));
      const wrapper = mountActions({
        postMeeting: { mode: 'ask', moved: false, stage },
      });

      await find(wrapper, 'meeting-post-move-confirm').trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain(`${DAY}.MOVE_FAILED`);
      expect(wrapper.emitted('changed')).toBeUndefined();
    });
  });

  it('every button is at least 44 px tall', () => {
    const wrapper = mountActions({
      meeting: meeting({ outcome: 'no_show' }),
      postMeeting: { mode: 'ask', moved: false, stage: { id: 1, name: 'X' } },
    });

    const buttons = wrapper.findAll('button');
    expect(buttons.length).toBeGreaterThan(3);
    buttons.forEach(button => {
      expect(button.classes()).toContain('min-h-11');
    });
  });
});
