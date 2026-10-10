import { mount } from '@vue/test-utils';
import CrmCalendarMonthGrid from './CrmCalendarMonthGrid.vue';

const LOCATION = 'CRM_KANBAN.CALENDAR.MEETING_LOCATION';

// A célula densa só mostra os chips: o popover real não importa aqui.
const PopoverStub = { template: '<div><slot name="default" /></div>' };

const meeting = (id, day, extra = {}) => ({
  id: `meeting_${id}`,
  event_type: 'meeting',
  title: `Reunião ${id}`,
  starts_at: `2026-10-${day}T14:00:00Z`,
  status: 'scheduled',
  ...extra,
});

const mountGrid = events =>
  mount(CrmCalendarMonthGrid, {
    props: { cursorDate: new Date('2026-10-15T12:00:00Z'), events },
    global: { stubs: { Popover: PopoverStub } },
  });

const meetingIcon = wrapper => wrapper.find('button span[aria-hidden="true"]');

describe('CrmCalendarMonthGrid: local da reunião', () => {
  it.each([
    ['whatsapp_video', 'WHATSAPP_VIDEO', 'i-lucide-video'],
    ['whatsapp_voice', 'WHATSAPP_VOICE', 'i-lucide-phone'],
    ['custom_link', 'CUSTOM_LINK', 'i-lucide-link'],
    ['in_person', 'IN_PERSON', 'i-lucide-map-pin'],
  ])(
    'reunião interna %s mostra o ícone e a dica do local, nunca Meet nem Teams',
    (type, labelKey, icon) => {
      const wrapper = mountGrid([
        meeting(1, '15', { provider: 'internal', online_meeting_type: type }),
      ]);
      const span = meetingIcon(wrapper);

      expect(span.classes()).toContain(icon);
      expect(span.classes()).not.toContain('i-logos-google-meet');
      expect(span.classes()).not.toContain('i-logos-microsoft-teams');
      expect(span.attributes('title')).toBe(`${LOCATION}.${labelKey}`);
      wrapper.unmount();
    }
  );

  it('reunião do Google segue com o ícone do Meet e sem dica nova', () => {
    const wrapper = mountGrid([
      meeting(2, '15', {
        provider: 'google',
        online_meeting_type: 'google_meet',
      }),
    ]);
    const span = meetingIcon(wrapper);

    expect(span.classes()).toContain('i-logos-google-meet');
    expect(span.attributes('title')).toBeUndefined();
    wrapper.unmount();
  });

  it('reunião da Microsoft segue com o ícone do Teams e sem dica nova', () => {
    const wrapper = mountGrid([
      meeting(3, '16', { provider: 'microsoft', online_meeting_type: 'teams' }),
    ]);
    const span = meetingIcon(wrapper);

    expect(span.classes()).toContain('i-logos-microsoft-teams');
    expect(span.attributes('title')).toBeUndefined();
    wrapper.unmount();
  });

  describe('dia cheio (chip com a contagem)', () => {
    const dayOf = (provider, type, from) =>
      [1, 2, 3, 4].map(n =>
        meeting(from + n, '20', { provider, online_meeting_type: type })
      );

    it('só reuniões internas: o chip não usa o ícone do Meet', () => {
      const wrapper = mountGrid(dayOf('internal', 'whatsapp_video', 10));
      const chip = wrapper.find('button[aria-label] span span');

      expect(chip.classes()).toContain('i-lucide-calendar-clock');
      expect(chip.classes()).not.toContain('i-logos-google-meet');
      wrapper.unmount();
    });

    it('só reuniões do Google: o chip continua com o ícone do Meet', () => {
      const wrapper = mountGrid(dayOf('google', 'google_meet', 20));
      const chip = wrapper.find('button[aria-label] span span');

      expect(chip.classes()).toContain('i-logos-google-meet');
      wrapper.unmount();
    });

    it('mistura de internas e Google: o chip continua com o ícone do Meet', () => {
      const wrapper = mountGrid([
        ...dayOf('google', 'google_meet', 30).slice(0, 3),
        meeting(99, '20', {
          provider: 'internal',
          online_meeting_type: 'in_person',
        }),
      ]);
      const chip = wrapper.find('button[aria-label] span span');

      expect(chip.classes()).toContain('i-logos-google-meet');
      wrapper.unmount();
    });
  });
});
