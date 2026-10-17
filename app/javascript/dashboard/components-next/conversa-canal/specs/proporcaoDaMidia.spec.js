import {
  FORMATOS,
  PROPORCAO_MINIMA,
  formatoDaMidia,
} from '../midia/proporcaoDaMidia';

// Teste do Rodrigo em 17/10 (conta 16): vídeo 9:16 e 16:9 fora do padrão do WhatsApp.
describe('formatoDaMidia (#1702)', () => {
  it('16:9 e 3:2 ficam deitados: 330 de largura, altura pela proporção', () => {
    expect(formatoDaMidia(1920, 1080)).toBe(FORMATOS.deitada);
    expect(formatoDaMidia(1500, 1000)).toBe(FORMATOS.deitada);
  });

  it('quadrada e 3:4 ficam em pé: 330 de altura, largura pela proporção', () => {
    expect(formatoDaMidia(1000, 1000)).toBe(FORMATOS.deitada);
    expect(formatoDaMidia(900, 1200)).toBe(FORMATOS.emPe);
  });

  it('9:16 fica alta e cortada, sem afinar além de 0,72', () => {
    expect(formatoDaMidia(1080, 1920)).toBe(FORMATOS.alta);
    expect(FORMATOS.alta).toContain('w-[238px]');
    expect(Math.round(330 * PROPORCAO_MINIMA)).toBe(238);
  });

  it('sem medidas (antes de carregar) sai deitada', () => {
    expect(formatoDaMidia(0, 0)).toBe(FORMATOS.deitada);
    expect(formatoDaMidia(undefined, 720)).toBe(FORMATOS.deitada);
  });
});
