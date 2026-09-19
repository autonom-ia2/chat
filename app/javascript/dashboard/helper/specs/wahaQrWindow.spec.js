import {
  qrSecondsLeft,
  formatSeconds,
  FIRST_QR_SECONDS,
  NEXT_QR_SECONDS,
  MAX_QR_CODES,
} from '../wahaQrWindow';

describe('qrSecondsLeft', () => {
  it('returns the whole pairing window when the first code just appeared', () => {
    expect(qrSecondsLeft(1, 0)).toBe(
      FIRST_QR_SECONDS + (MAX_QR_CODES - 1) * NEXT_QR_SECONDS
    );
  });

  it('counts down inside the current code', () => {
    expect(qrSecondsLeft(1, 45)).toBe(15 + 100);
    expect(qrSecondsLeft(3, 5)).toBe(15 + 60);
  });

  it('never goes below the codes still to come', () => {
    expect(qrSecondsLeft(2, 90)).toBe(80);
  });

  it('reaches zero on the last code', () => {
    expect(qrSecondsLeft(MAX_QR_CODES, NEXT_QR_SECONDS)).toBe(0);
    expect(qrSecondsLeft(9, 30)).toBe(0);
  });
});

describe('formatSeconds', () => {
  it('formats as m:ss', () => {
    expect(formatSeconds(160)).toBe('2:40');
    expect(formatSeconds(9)).toBe('0:09');
    expect(formatSeconds(-3)).toBe('0:00');
  });
});
