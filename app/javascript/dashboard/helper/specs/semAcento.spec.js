import { semAcento } from '../semAcento';

// Busca sem acento e sem caixa (#1786, hoje em helper comum pelo #1895).
describe('semAcento', () => {
  it('tira acento e caixa', () => {
    expect(semAcento('Coração Ação')).toBe('coracao acao');
  });

  it('vazio ou ausente vira texto vazio', () => {
    expect(semAcento(undefined)).toBe('');
    expect(semAcento(null)).toBe('');
  });
});
