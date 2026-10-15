import {
  stoppedKeyFor,
  timelockEndFor,
  statusKeyFor,
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
    expect(statusKeyFor({ status: 'failed' })).toBe('FAILED');
    expect(statusKeyFor({ status: 'disconnected' })).toBe('DISCONNECTED');
    expect(statusKeyFor({ status: 'awaiting_scan' })).toBe('AWAITING');
  });
});
