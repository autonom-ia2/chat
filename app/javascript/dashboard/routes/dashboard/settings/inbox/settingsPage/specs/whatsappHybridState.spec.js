import {
  stoppedKeyFor,
  timelockEndFor,
  statusKeyFor,
  phaseFor,
  limitDateTime,
  limitDate,
  phoneLabel,
  STATUS_VISUALS,
} from '../whatsappHybridState';

describe('stoppedKeyFor', () => {
  it('says WhatsApp removed the device when a connected session fails', () => {
    expect(stoppedKeyFor({ status: 'failed', phone: '5511999990000' })).toBe(
      'REMOVED'
    );
  });

  it('says the QR code expired when the session never connected', () => {
    expect(stoppedKeyFor({ status: 'failed', phone: null })).toBe('EXPIRED');
    expect(stoppedKeyFor({ status: 'failed' })).toBe('EXPIRED');
  });

  it('keeps the disconnected state, with or without a phone', () => {
    expect(stoppedKeyFor({ status: 'disconnected' })).toBe('DISCONNECTED');
    expect(
      stoppedKeyFor({ status: 'disconnected', phone: '5511999990000' })
    ).toBe('DISCONNECTED');
  });
});

describe('timelockEndFor', () => {
  const now = Date.UTC(2026, 9, 13, 18, 30);
  const later = Date.UTC(2026, 9, 14, 0, 26) / 1000;

  it('returns when the limit ends while it is active', () => {
    const end = timelockEndFor(
      { timelock: { active: true, ends_at: later } },
      now
    );

    expect(end).toEqual(new Date(later * 1000));
  });

  it('returns true for an active limit without an end', () => {
    expect(timelockEndFor({ timelock: { active: true } }, now)).toBe(true);
  });

  it('returns null without a limit, when inactive or already over', () => {
    expect(timelockEndFor({}, now)).toBeNull();
    expect(
      timelockEndFor({ timelock: { active: false, ends_at: later } }, now)
    ).toBeNull();
    expect(
      timelockEndFor(
        { timelock: { active: true, ends_at: now / 1000 - 60 } },
        now
      )
    ).toBeNull();
  });
});

describe('statusKeyFor', () => {
  it('shows paused before the engine state (the stopped session is on purpose)', () => {
    expect(
      statusKeyFor({ status: 'disconnected', paused: true, phone: '5511' })
    ).toBe('PAUSED');
  });

  it('keeps the other states', () => {
    expect(statusKeyFor({ status: 'not_connected' })).toBe('NOT_CONNECTED');
    expect(statusKeyFor({ status: 'connected', connected: true })).toBe(
      'CONNECTED'
    );
    expect(statusKeyFor({ status: 'failed', phone: '5511' })).toBe('REMOVED');
    expect(statusKeyFor({ status: 'failed' })).toBe('EXPIRED');
    expect(statusKeyFor({ status: 'disconnected' })).toBe('DISCONNECTED');
    expect(statusKeyFor({ status: 'awaiting_scan' })).toBe('AWAITING');
  });
});

describe('phaseFor', () => {
  it('gives each state one situation box', () => {
    expect(phaseFor({ status: 'loading' })).toBe('loading');
    expect(phaseFor({ status: 'unavailable' })).toBe('unavailable');
    expect(phaseFor({ status: 'not_connected' })).toBe('not_connected');
    expect(phaseFor({ status: 'awaiting_scan' })).toBe('pairing');
    expect(phaseFor({ status: 'connecting' })).toBe('pairing');
    expect(phaseFor({ status: 'failed' })).toBe('stopped');
    expect(phaseFor({ status: 'disconnected' })).toBe('stopped');
    expect(
      phaseFor({ status: 'connected', connected: true, same_number: true })
    ).toBe('connected');
    expect(
      phaseFor({ status: 'connected', connected: true, same_number: false })
    ).toBe('wrong_number');
  });

  it('puts the pause before the engine state', () => {
    expect(phaseFor({ status: 'disconnected', paused: true })).toBe('paused');
  });
});

describe('limit dates (chat#1487)', () => {
  // 2026-10-14 02:30 UTC = 13/10 23:30 em São Paulo e 14/10 11:30 em Tóquio.
  const endsAt = Date.UTC(2026, 9, 14, 2, 30) / 1000;

  it('uses the account time zone and language, not the browser', () => {
    expect(
      limitDateTime(endsAt, { locale: 'pt_BR', timeZone: 'America/Sao_Paulo' })
    ).toBe('13/10, 23:30');
    expect(
      limitDateTime(endsAt, { locale: 'pt_BR', timeZone: 'Asia/Tokyo' })
    ).toBe('14/10, 11:30');
    expect(
      limitDate(endsAt, { locale: 'pt_BR', timeZone: 'America/Sao_Paulo' })
    ).toBe('13/10/2026');
    expect(limitDate(endsAt, { locale: 'en', timeZone: 'Asia/Tokyo' })).toBe(
      '10/14/2026'
    );
  });
});

describe('expired QR chip (chat#1487)', () => {
  it('says expired, like the title, with a matching icon', () => {
    expect(statusKeyFor({ status: 'failed', phone: null })).toBe('EXPIRED');
    expect(STATUS_VISUALS.EXPIRED.icon).toBe('i-lucide-timer-off');
  });
});

describe('phoneLabel (chat#1487)', () => {
  it('formats the raw digits with the country code', () => {
    expect(phoneLabel('551140001487')).toBe('+55 11 4000-1487');
    expect(phoneLabel('5511999993846')).toBe('+55 11 99999-3846');
  });

  it('keeps empty as empty', () => {
    expect(phoneLabel(null)).toBe('');
    expect(phoneLabel('')).toBe('');
  });
});
