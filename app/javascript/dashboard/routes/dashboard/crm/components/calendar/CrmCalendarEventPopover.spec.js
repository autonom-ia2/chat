// O literal "javascript:" é o dado de ataque que estes testes precisam recusar.
/* eslint-disable no-script-url */
import { mount } from '@vue/test-utils';
import CrmCalendarEventPopover from './CrmCalendarEventPopover.vue';

const LOCATION = 'CRM_KANBAN.CALENDAR.MEETING_LOCATION';

const meeting = (extra = {}) => ({
  id: 'meeting_1',
  event_type: 'meeting',
  title: 'Reunião',
  starts_at: '2026-10-15T14:00:00Z',
  status: 'scheduled',
  ...extra,
});

const mountPopover = event =>
  mount(CrmCalendarEventPopover, {
    props: { event },
    global: {
      stubs: {
        Button: {
          props: ['label'],
          template: '<button :data-label="label" @click="$emit(\'click\')" />',
        },
      },
    },
  });

const joinButton = wrapper =>
  wrapper.find('button[data-label="CRM_KANBAN.CALENDAR.EVENT.JOIN_MEETING"]');

describe('CrmCalendarEventPopover: local da reunião', () => {
  beforeEach(() => {
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  afterEach(() => vi.restoreAllMocks());

  it.each([
    ['whatsapp_video', 'WHATSAPP_VIDEO'],
    ['whatsapp_voice', 'WHATSAPP_VOICE'],
    ['custom_link', 'CUSTOM_LINK'],
    ['in_person', 'IN_PERSON'],
  ])('reunião interna %s mostra o rótulo do local', (type, labelKey) => {
    const wrapper = mountPopover(
      meeting({ provider: 'internal', online_meeting_type: type })
    );

    expect(wrapper.find('[data-test="meeting-location"]').text()).toBe(
      `${LOCATION}.${labelKey}`
    );
    wrapper.unmount();
  });

  it('Google e Microsoft não ganham linha de local e mantêm o botão de entrar', async () => {
    const url = 'https://meet.google.com/abc';
    const wrapper = mountPopover(
      meeting({
        provider: 'google',
        online_meeting_type: 'google_meet',
        online_meeting_url: url,
      })
    );

    expect(wrapper.find('[data-test="meeting-location"]').exists()).toBe(false);
    await joinButton(wrapper).trigger('click');
    expect(window.open).toHaveBeenCalledWith(
      url,
      '_blank',
      'noopener,noreferrer'
    );
    wrapper.unmount();
  });

  it('link do agente http/https abre; javascript: não vira botão nem abre', async () => {
    const safe = mountPopover(
      meeting({
        provider: 'internal',
        online_meeting_type: 'custom_link',
        online_meeting_url: 'https://sala.exemplo.com/1',
      })
    );
    await joinButton(safe).trigger('click');
    expect(window.open).toHaveBeenCalledWith(
      'https://sala.exemplo.com/1',
      '_blank',
      'noopener,noreferrer'
    );
    safe.unmount();

    window.open.mockClear();
    const unsafe = mountPopover(
      meeting({
        provider: 'internal',
        online_meeting_type: 'custom_link',
        online_meeting_url: 'javascript:alert(1)',
      })
    );
    expect(joinButton(unsafe).exists()).toBe(false);
    expect(window.open).not.toHaveBeenCalled();
    unsafe.unmount();
  });
});
