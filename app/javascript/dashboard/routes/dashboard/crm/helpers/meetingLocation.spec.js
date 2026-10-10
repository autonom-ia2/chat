// O literal "javascript:" é o dado de ataque que estes testes precisam recusar.
/* eslint-disable no-script-url */
import {
  isInternalMeeting,
  resolveMeetingLocation,
  safeWebUrl,
} from './meetingLocation';

const LOCATION = 'CRM_KANBAN.CALENDAR.MEETING_LOCATION';

describe('safeWebUrl', () => {
  it('aceita http e https', () => {
    expect(safeWebUrl('https://meet.exemplo.com/sala')).toBe(
      'https://meet.exemplo.com/sala'
    );
    expect(safeWebUrl('  http://exemplo.com/a ')).toBe('http://exemplo.com/a');
  });

  it('recusa javascript:, data:, mailto: e texto solto', () => {
    [
      'javascript:alert(1)',
      'data:text/html,x',
      'mailto:a@b.com',
      'sala 1',
    ].forEach(value => expect(safeWebUrl(value)).toBe(''));
    expect(safeWebUrl(' JaVaScRiPt:alert(1)')).toBe('');
    expect(safeWebUrl(null)).toBe('');
    expect(safeWebUrl(undefined)).toBe('');
    expect(safeWebUrl(10)).toBe('');
  });
});

describe('resolveMeetingLocation', () => {
  it.each([
    ['whatsapp_video', `${LOCATION}.WHATSAPP_VIDEO`, 'i-lucide-video'],
    ['whatsapp_voice', `${LOCATION}.WHATSAPP_VOICE`, 'i-lucide-phone'],
    ['custom_link', `${LOCATION}.CUSTOM_LINK`, 'i-lucide-link'],
    ['in_person', `${LOCATION}.IN_PERSON`, 'i-lucide-map-pin'],
    ['no_online', `${LOCATION}.NO_ONLINE`, 'i-lucide-calendar-clock'],
  ])(
    'reunião interna %s tem o rótulo e o ícone próprios',
    (type, labelKey, icon) => {
      const location = resolveMeetingLocation({
        provider: 'internal',
        online_meeting_type: type,
      });

      expect(location).toMatchObject({
        isInternal: true,
        type,
        labelKey,
        icon,
      });
    }
  );

  it('lê location_type quando online_meeting_type não vem', () => {
    const location = resolveMeetingLocation({
      provider: 'internal',
      location_type: 'in_person',
    });

    expect(location.labelKey).toBe(`${LOCATION}.IN_PERSON`);
  });

  it('interna com tipo de provedor não herda a marca do Meet nem do Teams', () => {
    ['teams', 'google_meet', undefined].forEach(type => {
      const location = resolveMeetingLocation({
        provider: 'internal',
        online_meeting_type: type,
      });

      expect(location.isInternal).toBe(true);
      expect(location.icon).toBe('i-lucide-calendar-clock');
      expect(location.joinUrl).toBe('');
    });
  });

  it('só o link do agente devolve endereço, e só se for http/https', () => {
    const base = { provider: 'internal', online_meeting_type: 'custom_link' };

    expect(
      resolveMeetingLocation({ ...base, online_meeting_url: 'https://a.com/x' })
        .joinUrl
    ).toBe('https://a.com/x');
    expect(
      resolveMeetingLocation({
        ...base,
        online_meeting_url: 'javascript:alert(1)',
      }).joinUrl
    ).toBe('');
    expect(
      resolveMeetingLocation({
        provider: 'internal',
        online_meeting_type: 'whatsapp_video',
        online_meeting_url: 'https://a.com/x',
      }).joinUrl
    ).toBe('');
  });

  it('Google e Microsoft ficam como estavam: sem rótulo novo e link intacto', () => {
    [
      { provider: 'google', online_meeting_type: 'google_meet' },
      { provider: 'microsoft', online_meeting_type: 'teams' },
      { provider: 'google', online_meeting_type: 'no_online' },
      { online_meeting_type: 'teams' },
    ].forEach(meeting => {
      const location = resolveMeetingLocation({
        ...meeting,
        online_meeting_url: 'https://meet.google.com/abc',
      });

      expect(location).toMatchObject({
        isInternal: false,
        labelKey: '',
        icon: '',
        joinUrl: 'https://meet.google.com/abc',
      });
    });
  });
});

describe('isInternalMeeting', () => {
  it('reconhece pelo provedor ou por tipo que só existe em reunião interna', () => {
    expect(isInternalMeeting({ provider: 'internal' })).toBe(true);
    expect(isInternalMeeting({ online_meeting_type: 'whatsapp_voice' })).toBe(
      true
    );
    expect(isInternalMeeting({ provider: 'google' })).toBe(false);
    expect(isInternalMeeting(null)).toBe(false);
  });
});
