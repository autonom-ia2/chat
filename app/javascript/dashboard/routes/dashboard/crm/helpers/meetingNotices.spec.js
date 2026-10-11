import { skipReasonKey } from './meetingNotices';

describe('skipReasonKey', () => {
  it('dá texto próprio aos motivos da WAHA sem conversa (#1270)', () => {
    expect(skipReasonKey('no_whatsapp')).toBe('NO_WHATSAPP');
    expect(skipReasonKey('waha_unavailable')).toBe('WAHA_UNAVAILABLE');
    expect(skipReasonKey('waha_refused')).toBe('WAHA_REFUSED');
  });

  it('mantém o motivo antigo da janela da WAHA para avisos já gravados', () => {
    expect(skipReasonKey('waha_outside_window')).toBe('WAHA_OUTSIDE_WINDOW');
  });

  it('motivo desconhecido cai em OTHER', () => {
    expect(skipReasonKey('qualquer_coisa')).toBe('OTHER');
    expect(skipReasonKey(undefined)).toBe('OTHER');
  });
});
