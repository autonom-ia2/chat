import { stoppedKeyFor } from '../whatsappHybridState';

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
