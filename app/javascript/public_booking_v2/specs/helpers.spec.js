import {
  DEFAULT_BRAND_COLOR,
  applyBrandColor,
  contrastWithWhite,
  isHexColor,
  readableBrandColor,
} from '../helpers/brand';
import {
  bookingDays,
  dateInZone,
  isValidTimeZone,
  timeLabel,
} from '../helpers/datetime';
import { locationKey } from '../helpers/locations';
import {
  formatNational,
  isPlausiblePhone,
  looksLikeEmail,
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
    expect(bookingDays('America/Sao_Paulo', 2, now)).toEqual([
      '2026-10-12',
      '2026-10-13',
      '2026-10-14',
    ]);
    expect(bookingDays('Asia/Tokyo', 0, now)).toEqual(['2026-10-13']);
  });

  it('shows times in the client time zone', () => {
    expect(timeLabel('2026-10-13T15:00:00-03:00', 'pt_BR', 'UTC')).toBe(
      '18:00'
    );
    expect(
      timeLabel('2026-10-13T15:00:00-03:00', 'pt_BR', 'America/Sao_Paulo')
    ).toBe('15:00');
  });

  it('rejects an invalid time zone explicitly', () => {
    expect(isValidTimeZone('America/Sao_Paulo')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
    expect(isValidTimeZone('')).toBe(false);
  });
});

describe('routes and locations', () => {
  it('reads /book/:slug, /b/:code and preview', () => {
    expect(parseRoute('/book/conversa', '?preview=tk')).toEqual({
      code: null,
      slug: 'conversa',
      preview: 'tk',
    });
    expect(parseRoute('/b/Xk4p9Q', '?preview=tk')).toEqual({
      code: 'Xk4p9Q',
      slug: null,
    });
    expect(parseRoute('/other', '')).toEqual({ code: null, slug: null });
  });

  it('maps unknown location types to a generic label', () => {
    expect(locationKey('whatsapp_video')).toBe('WHATSAPP_VIDEO');
    expect(locationKey('zoom')).toBe('OTHER');
    expect(locationKey(undefined)).toBe('OTHER');
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
