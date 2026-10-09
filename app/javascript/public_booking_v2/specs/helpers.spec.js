import {
  DEFAULT_BRAND_COLOR,
  applyBrandColor,
  contrastWithWhite,
  isHexColor,
  readableBrandColor,
} from '../helpers/brand';
import { googleCalendarUrl } from '../helpers/calendar';
import {
  bookingDays,
  dateInZone,
  isValidTimeZone,
  sameClock,
  slotLabel,
  timeLabel,
} from '../helpers/datetime';
import {
  locationHint,
  locationKey,
  locationName,
  locationOptions,
} from '../helpers/locations';
import {
  caretAfterDigits,
  formatNational,
  isPlausiblePhone,
  looksLikeEmail,
  normalizeNational,
  onlyDigits,
  toInternational,
} from '../helpers/phone';
import { newRequestId } from '../helpers/requestId';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';
import { parseRoute } from '../composables/useBookingFlow';

// Montado em partes para o lint não confundir o teste com uso de `javascript:`.
const SCRIPT = ['java', 'script:'].join('');

describe('brand color', () => {
  it('accepts only #RRGGBB', () => {
    expect(isHexColor('#0B7A5A')).toBe(true);
    expect(isHexColor('#0b7a5a')).toBe(true);
    ['red', '#fff', '#12345g', 'url(x)', '', null, 123].forEach(value => {
      expect(isHexColor(value)).toBe(false);
    });
  });

  it('ignores an invalid color and uses the default', () => {
    expect(readableBrandColor('red; background: url(x)')).toBe(
      DEFAULT_BRAND_COLOR
    );
    const root = document.createElement('div');
    applyBrandColor(`${SCRIPT}alert(1)`, root);
    expect(root.style.getPropertyValue('--brand')).toBe(DEFAULT_BRAND_COLOR);
  });

  it('keeps a readable color as it is', () => {
    expect(readableBrandColor('#0B7A5A')).toBe('#0b7a5a');
  });

  it('darkens a low-contrast color until white text reaches AA', () => {
    const fixed = readableBrandColor('#FFFF00');
    expect(fixed).not.toBe('#ffff00');
    expect(contrastWithWhite(fixed)).toBeGreaterThanOrEqual(4.5);
  });
});

describe('safe urls', () => {
  it('never lets javascript:, data: or vbscript: through', () => {
    [
      `${SCRIPT}alert(1)`,
      ` ${SCRIPT.toUpperCase()}alert(1)`,
      'data:text/html,<b>x</b>',
      'vbscript:msgbox(1)',
    ].forEach(value => {
      expect(safeAbsoluteUrl(value)).toBeNull();
      expect(safeUrl(value)).toBeNull();
    });
  });

  it('accepts http/https and same-site paths', () => {
    expect(safeAbsoluteUrl('https://meet.example.com/x')).toBe(
      'https://meet.example.com/x'
    );
    expect(safeAbsoluteUrl('/public/api/v2/ics/abc')).toBeNull();
    expect(safeUrl('/public/api/v2/ics/abc')).toBe(
      `${window.location.origin}/public/api/v2/ics/abc`
    );
  });
});

describe('phone', () => {
  it('keeps only digits without regex', () => {
    expect(onlyDigits('+55 (11) 98888-0000')).toBe('5511988880000');
  });

  it('formats a Brazilian number while typing', () => {
    expect(formatNational('', '55')).toBe('');
    expect(formatNational('11', '55')).toBe('(11');
    expect(formatNational('119888', '55')).toBe('(11) 9888');
    expect(formatNational('1133334444', '55')).toBe('(11) 3333-4444');
    expect(formatNational('11988880000', '55')).toBe('(11) 98888-0000');
    expect(formatNational('119888800001', '55')).toBe('(11) 98888-0000');
    expect(formatNational('2025550100', '1')).toBe('2025550100');
  });

  it('checks plausible lengths and builds the international number', () => {
    expect(isPlausiblePhone('55', '11988880000')).toBe(true);
    expect(isPlausiblePhone('55', '1198888')).toBe(false);
    expect(isPlausiblePhone('', '11988880000')).toBe(false);
    expect(isPlausiblePhone('1', '2025550100')).toBe(true);
    expect(toInternational('55', '(11) 98888-0000')).toBe('+5511988880000');
  });

  it('drops the country code and the trunk zero from what was pasted', () => {
    expect(normalizeNational('+55 11 98765-4321', '55')).toBe('11987654321');
    expect(normalizeNational('0055 11 98765-4321', '55')).toBe('11987654321');
    expect(normalizeNational('5511987654321', '55')).toBe('11987654321');
    expect(normalizeNational('011 98765-4321', '55')).toBe('11987654321');
    expect(normalizeNational('55 98765-4321', '55', { pasted: true })).toBe(
      '987654321'
    );
    // DDD 55 digitado à mão continua sendo DDD.
    expect(normalizeNational('55987654321', '55')).toBe('55987654321');
    expect(normalizeNational('119888800001', '55')).toBe('11988880000');
    expect(normalizeNational('+1 202 555 0100', '1')).toBe('2025550100');
  });

  it('keeps the caret after the same digit when the mask changes', () => {
    expect(caretAfterDigits('(11) 98765-4321', 0)).toBe(0);
    expect(caretAfterDigits('(11) 98765-4321', 2)).toBe(3);
    expect(caretAfterDigits('(11) 98765-4321', 3)).toBe(6);
    expect(caretAfterDigits('(11) 98765-4321', 8)).toBe(12);
    expect(caretAfterDigits('(11) 9876', 20)).toBe(9);
  });

  it('does a light email check', () => {
    expect(looksLikeEmail('ana@exemplo.com')).toBe(true);
    ['ana', 'ana@', '@x.com', 'a@b', 'a b@x.com', 'a@@x.com', 'a@x.'].forEach(
      value => expect(looksLikeEmail(value)).toBe(false)
    );
  });
});

describe('dates and time zones', () => {
  it('lists the window days in the page time zone', () => {
    // 01:30 UTC on the 13th is still the 12th in São Paulo.
    const now = new Date('2026-10-13T01:30:00Z');
    expect(dateInZone(now, 'America/Sao_Paulo')).toBe('2026-10-12');
    expect(bookingDays('America/Sao_Paulo', 2, undefined, now)).toEqual([
      '2026-10-12',
      '2026-10-13',
      '2026-10-14',
    ]);
    expect(bookingDays('Asia/Tokyo', 0, undefined, now)).toEqual([
      '2026-10-13',
    ]);
  });

  it('shows times in the client time zone', () => {
    expect(timeLabel('2026-10-13T15:00:00-03:00', 'pt_BR', 'UTC')).toBe(
      '18:00'
    );
    expect(
      timeLabel('2026-10-13T15:00:00-03:00', 'pt_BR', 'America/Sao_Paulo')
    ).toBe('15:00');
  });

  it('offers only the weekdays the page works and caps the window at 90 days', () => {
    // 12/10/2026 é segunda-feira.
    const now = new Date('2026-10-12T12:00:00Z');
    expect(bookingDays('America/Sao_Paulo', 6, [1, 3, 5], now)).toEqual([
      '2026-10-12',
      '2026-10-14',
      '2026-10-16',
    ]);
    expect(bookingDays('America/Sao_Paulo', 365, undefined, now)).toHaveLength(
      91
    );
  });

  it('adds the day to a time that falls on another day for the client', () => {
    const iso = '2026-10-13T22:00:00-03:00';
    expect(slotLabel(iso, 'pt_BR', 'America/Sao_Paulo', '2026-10-13')).toBe(
      '22:00'
    );
    const tokyo = slotLabel(iso, 'pt_BR', 'Asia/Tokyo', '2026-10-13');
    expect(tokyo).toContain('10:00');
    expect(tokyo).toContain('14');
  });

  it('compares clocks, not zone names', () => {
    const at = new Date('2026-10-12T12:00:00Z');
    expect(sameClock('America/Sao_Paulo', 'America/Bahia', at)).toBe(true);
    expect(sameClock('America/Sao_Paulo', 'America/Manaus', at)).toBe(false);
  });

  it('rejects an invalid time zone explicitly', () => {
    expect(isValidTimeZone('America/Sao_Paulo')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
    expect(isValidTimeZone('')).toBe(false);
  });
});

describe('routes and locations', () => {
  it('reads /book/:slug, /b/:code, preview and stop_notices', () => {
    expect(parseRoute('/book/conversa', '?preview=tk')).toEqual({
      code: null,
      slug: 'conversa',
      preview: 'tk',
    });
    expect(parseRoute('/b/Xk4p9Q', '?preview=tk')).toEqual({
      code: 'Xk4p9Q',
      slug: null,
      stopNotices: false,
    });
    expect(parseRoute('/b/Xk4p9Q', '?stop_notices=1')).toEqual({
      code: 'Xk4p9Q',
      slug: null,
      stopNotices: true,
    });
    expect(parseRoute('/b/Xk4p9Q', '?stop_notices=yes').stopNotices).toBe(
      false
    );
    expect(parseRoute('/other', '')).toEqual({ code: null, slug: null });
  });

  it('maps unknown location types to a generic label', () => {
    expect(locationKey('whatsapp_video')).toBe('WHATSAPP_VIDEO');
    expect(locationKey('zoom')).toBe('OTHER');
    expect(locationKey(undefined)).toBe('OTHER');
  });

  it('prefers the server label and shows the in-person address', () => {
    const t = (key, values) => (values ? `${key}:${values.address}` : key);
    expect(locationName({ type: 'in_person', label: 'Loja' }, t)).toBe('Loja');
    expect(locationName({ type: 'in_person' }, t)).toBe(
      'BOOKING_V2.LOCATION.IN_PERSON'
    );
    expect(locationHint({ type: 'in_person', address: 'Rua A' }, t)).toBe(
      'BOOKING_V2.ADDRESS:Rua A'
    );
    expect(locationHint({ type: 'whatsapp_video', address: 'x' }, t)).toBe(
      'BOOKING_V2.LOCATION_HINT.WHATSAPP_VIDEO'
    );
    expect(locationOptions([{ type: 'teams', label: 'Teams' }], t)).toEqual([
      {
        value: 'teams',
        label: 'Teams',
        hint: 'BOOKING_V2.LOCATION_HINT.TEAMS',
      },
    ]);
  });
});

describe('google calendar link', () => {
  it('builds the event template with title, UTC times and place only', () => {
    const url = new URL(
      googleCalendarUrl({
        title: 'Horário com Camila',
        startsAt: '2026-10-13T15:00:00-03:00',
        endsAt: '2026-10-13T15:30:00-03:00',
        location: 'Av. Paulista, 1000',
      })
    );
    expect(url.hostname).toBe('calendar.google.com');
    expect(url.searchParams.get('dates')).toBe(
      '20261013T180000Z/20261013T183000Z'
    );
    expect(url.searchParams.get('location')).toBe('Av. Paulista, 1000');
  });

  it('gives no link without valid times', () => {
    expect(googleCalendarUrl({ title: 'x', startsAt: '', endsAt: '' })).toBe(
      null
    );
  });
});

describe('request id', () => {
  it('uses crypto.randomUUID when the browser has it', () => {
    const cryptoApi = {
      randomUUID: () => 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    };
    expect(newRequestId(cryptoApi)).toBe(
      'f47ac10b-58cc-4372-a567-0e02b2c3d479'
    );
  });

  it('falls back to 16 random bytes in hex without randomUUID', () => {
    const cryptoApi = {
      getRandomValues: bytes => bytes.map((_, index) => index * 17),
    };
    expect(newRequestId(cryptoApi)).toBe('00112233445566778899aabbccddeeff');
  });

  it('draws a different key each time from the real crypto', () => {
    const first = newRequestId();
    expect(first.length).toBe(36);
    expect([...first].every(char => '0123456789abcdef-'.includes(char))).toBe(
      true
    );
    expect(newRequestId()).not.toBe(first);
  });
});
