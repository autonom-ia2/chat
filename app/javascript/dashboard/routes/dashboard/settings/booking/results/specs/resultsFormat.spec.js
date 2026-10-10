import {
  barWidthClass,
  isEmptyTotals,
  numberLabelKey,
  originLabelKey,
  timeAgo,
} from '../resultsFormat';

// Painel de resultados (#1194): formatação sem estado.
describe('resultsFormat', () => {
  it('considera vazio só quando os cinco números são zero', () => {
    const zero = { sent: 0, opened: 0, booked: 0, attended: 0, no_show: 0 };
    expect(isEmptyTotals(zero)).toBe(true);
    expect(isEmptyTotals(null)).toBe(true);
    expect(isEmptyTotals({ ...zero, no_show: 1 })).toBe(false);
    // "confirmaram" sozinho não é um dos cinco cartões.
    expect(isEmptyTotals({ ...zero, confirmed: 3 })).toBe(true);
  });

  it('mede a barra em doze partes, com pelo menos uma parte para quem tem algum', () => {
    expect(barWidthClass(0, 10)).toBe('w-0');
    expect(barWidthClass(10, 10)).toBe('w-full');
    expect(barWidthClass(5, 10)).toBe('w-6/12');
    expect(barWidthClass(1, 1000)).toBe('w-1/12');
    expect(barWidthClass(3, 0)).toBe('w-0');
  });

  it('dá a chave de cada número e origem, com conversa para origem desconhecida', () => {
    expect(numberLabelKey('no_show')).toBe(
      'BOOKING.RESULTS.NUMBERS.NO_SHOW.LABEL'
    );
    expect(originLabelKey('public_link')).toBe(
      'BOOKING.RESULTS.ORIGINS.PUBLIC_LINK'
    );
    expect(originLabelKey('outra')).toBe(
      'BOOKING.RESULTS.ORIGINS.CONVERSATION'
    );
  });

  it('diz há quanto tempo, no idioma da pessoa', () => {
    const now = Date.parse('2026-10-09T15:00:00Z');
    expect(timeAgo('2026-10-07T15:00:00Z', 'pt_BR', now)).toBe('anteontem');
    expect(timeAgo('2026-10-06T14:00:00Z', 'pt_BR', now)).toBe('há 3 dias');
    expect(timeAgo('2026-10-09T12:00:00Z', 'pt_BR', now)).toBe('há 3 horas');
    expect(timeAgo('2026-10-09T15:00:00Z', 'en', now)).toBe('now');
    expect(timeAgo('não é data', 'pt_BR', now)).toBe('');
  });
});
