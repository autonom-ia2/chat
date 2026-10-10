import {
  canCall,
  canRebook,
  canRemind,
  formatClientPhone,
  meetingIdOf,
  refusalFrom,
} from './meetingDay';

// Quando oferecer as ações do dia da reunião (#1193, J4) e a recusa leiga.
const NOW = new Date('2026-10-19T14:00:00Z');
const booking = (extra = {}) => ({
  booking: true,
  status: 'scheduled',
  starts_at: '2026-10-20T13:00:00Z',
  confirmation_status: 'pending',
  notices_stopped: false,
  ...extra,
});

describe('meetingDay', () => {
  it('offers "Lembrar" only for a future booking meeting the client did not confirm nor stop', () => {
    expect(canRemind(booking(), NOW)).toBe(true);
    expect(
      canRemind(booking({ confirmation_status: 'change_requested' }), NOW)
    ).toBe(true);
    expect(canRemind(booking({ confirmation_status: 'confirmed' }), NOW)).toBe(
      false
    );
    expect(canRemind(booking({ notices_stopped: true }), NOW)).toBe(false);
    expect(canRemind(booking({ booking: false }), NOW)).toBe(false);
    expect(canRemind(booking({ status: 'canceled' }), NOW)).toBe(false);
    expect(canRemind(booking({ starts_at: '2026-10-19T13:59:00Z' }), NOW)).toBe(
      false
    );
    expect(canRemind(booking({ starts_at: 'not a date' }), NOW)).toBe(false);
    expect(canRemind(null, NOW)).toBe(false);
  });

  it('offers the new link only when the client of a booking meeting did not show up', () => {
    expect(canRebook(booking({ outcome: 'no_show' }))).toBe(true);
    expect(canRebook(booking({ outcome: 'held' }))).toBe(false);
    expect(canRebook(booking({ outcome: null }))).toBe(false);
    expect(canRebook({ booking: false, outcome: 'no_show' })).toBe(false);
  });

  it('offers the WhatsApp call for WhatsApp meetings with a conversation or a number', () => {
    const client = { conversation_id: null, whatsapp_url: 'https://wa.me/55' };
    expect(canCall({ location_type: 'whatsapp_video', client })).toBe(true);
    expect(canCall({ online_meeting_type: 'whatsapp_voice', client })).toBe(
      true
    );
    expect(
      canCall({
        location_type: 'whatsapp_video',
        client: { conversation_id: 4 },
      })
    ).toBe(true);
    expect(canCall({ location_type: 'in_person', client })).toBe(false);
    expect(canCall({ location_type: 'whatsapp_video', client: {} })).toBe(
      false
    );
    expect(canCall({ location_type: 'whatsapp_video' })).toBe(false);
  });

  it('turns the server refusal into a lay key and keeps the link to copy', () => {
    const error = (data = {}) => ({ response: { data } });

    expect(
      refusalFrom(
        error({ error: 'crm.booking_v2.cannot_reply', url: 'https://x/b/AB' })
      )
    ).toEqual({ key: 'CANNOT_REPLY', url: 'https://x/b/AB' });
    expect(refusalFrom(error({ error: 'crm.booking_v2.stopped' }))).toEqual({
      key: 'STOPPED',
      url: '',
    });
    // Link para remarcar tocado de novo em menos de 10 minutos.
    expect(
      refusalFrom(error({ error: 'crm.booking_v2.recently_sent' }))
    ).toEqual({ key: 'RECENTLY_SENT', url: '' });
    expect(refusalFrom(error({ error: 'crm.booking_v2.unknown' }))).toEqual({
      key: 'OTHER',
      url: '',
    });
    expect(refusalFrom(new Error('network'))).toEqual({
      key: 'OTHER',
      url: '',
    });
  });

  it('formats the stored E.164 number for reading and keeps unknown text as it came', () => {
    expect(formatClientPhone('+5511912345678')).toBe('+55 11 91234 5678');
    expect(formatClientPhone('')).toBe('');
    expect(formatClientPhone(null)).toBe('');
    expect(formatClientPhone('abc')).toBe('abc');
  });

  it('reads the meeting id from a calendar event or from the meeting', () => {
    expect(meetingIdOf({ id: 'meeting_12' })).toBe('12');
    expect(meetingIdOf({ meeting_id: 9, id: 'meeting_12' })).toBe('9');
    expect(meetingIdOf({ id: 7 })).toBe('7');
    expect(meetingIdOf(null)).toBe('');
  });
});
