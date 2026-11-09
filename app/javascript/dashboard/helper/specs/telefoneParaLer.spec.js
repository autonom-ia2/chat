import { telefoneParaLer } from '../telefoneParaLer';

// #2213 — um formato só de telefone no painel: "(11) 98765-1201" no Brasil, internacional fora dele.
describe('telefoneParaLer (#2213)', () => {
  it('número do Brasil sai como a pessoa fala', () => {
    expect(telefoneParaLer('+5511987651201')).toBe('(11) 98765-1201');
    expect(telefoneParaLer('+551140001487')).toBe('(11) 4000-1487');
  });

  it('número de fora do Brasil sai no formato internacional', () => {
    expect(telefoneParaLer('+14155552671')).toBe('+1 415 555 2671');
    expect(telefoneParaLer('+351912345678')).toBe('+351 912 345 678');
  });

  it('sem número, devolve vazio', () => {
    expect(telefoneParaLer('')).toBe('');
    expect(telefoneParaLer(null)).toBe('');
    expect(telefoneParaLer(undefined)).toBe('');
  });

  it('o que não é telefone conhecido aparece como veio', () => {
    expect(telefoneParaLer('abc')).toBe('abc');
    expect(telefoneParaLer('5511987651201')).toBe('5511987651201');
  });
});
