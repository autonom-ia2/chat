import { normalizado, semAcento, soDigitos } from '../fonte/texto';

// Comparar texto digitado (#2894): só as marcas de acento somem; letra de outro
// alfabeto fica, senão a busca por um nome em cirílico viraria "tudo combina".
describe('semAcento', () => {
  it('tira o acento de nome em português', () => {
    expect(semAcento('José Conceição Ávila')).toBe('Jose Conceicao Avila');
  });

  it('mantém letra de outro alfabeto', () => {
    expect(semAcento('Иван')).toBe('Иван');
    expect(semAcento('Αλέξανδρος')).toBe('Αλεξανδρος');
    expect(semAcento('山田太郎')).toBe('山田太郎');
  });

  it('devolve vazio para vazio, nulo e indefinido', () => {
    expect(semAcento('')).toBe('');
    expect(semAcento(null)).toBe('');
    expect(semAcento(undefined)).toBe('');
  });
});

describe('normalizado', () => {
  it('põe em minúscula, sem acento e sem espaço nas pontas', () => {
    expect(normalizado('  ÁNA  ')).toBe('ana');
  });

  it('não zera nome em cirílico', () => {
    expect(normalizado('Иван')).toBe('иван');
  });
});

describe('soDigitos', () => {
  it('fica só com os números', () => {
    expect(soDigitos('+55 (11) 91031-0001')).toBe('5511910310001');
    expect(soDigitos(null)).toBe('');
  });
});
