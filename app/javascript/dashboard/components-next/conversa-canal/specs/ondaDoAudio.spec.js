import {
  BARRAS,
  NIVEIS,
  barrasDoAudio,
  carregarOnda,
  tempoDoAudio,
} from '../audio/ondaDoAudio';

describe('onda do áudio (#1702)', () => {
  it('uma barra por trecho, do ruído de fundo (chão) ao pico (teto)', () => {
    const amostras = Float32Array.from({ length: BARRAS * 100 }, (_, i) =>
      i < BARRAS * 50 ? 0.05 : -0.5
    );
    const barras = barrasDoAudio(amostras);
    expect(barras).toHaveLength(BARRAS);
    expect(barras[0]).toBe(0);
    expect(barras[BARRAS - 1]).toBe(NIVEIS - 1);
    expect(Math.max(...barras)).toBeLessThan(NIVEIS);
  });

  it('suaviza com as vizinhas: um pico isolado não vira dente solto', () => {
    const amostras = new Float32Array(BARRAS * 100).fill(0.05);
    amostras.fill(0.8, 20 * 100, 21 * 100);
    const barras = barrasDoAudio(amostras);
    expect(barras[20]).toBe(NIVEIS - 1);
    expect(barras[19]).toBeGreaterThan(0);
    expect(barras[19]).toBeLessThan(NIVEIS - 1);
    expect(barras[21]).toBe(barras[19]);
    expect(barras[10]).toBe(0);
  });

  it('som constante fica no alto, não no chão', () => {
    const barras = barrasDoAudio(new Float32Array(BARRAS * 100).fill(0.3));
    expect(barras).toEqual(Array(BARRAS).fill(NIVEIS - 1));
  });

  it('silêncio ou áudio vazio: barras no chão, sem quebrar', () => {
    expect(barrasDoAudio(new Float32Array(100))).toEqual(Array(BARRAS).fill(0));
    expect(barrasDoAudio(undefined)).toEqual(Array(BARRAS).fill(0));
    expect(barrasDoAudio(Float32Array.from([1]))).toHaveLength(BARRAS);
  });

  it('arquivo que não abre devolve null (o balão fica com barras neutras)', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({ ok: false });
    expect(await carregarOnda('https://exemplo.com/a.ogg')).toBeNull();
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('rede'));
    expect(await carregarOnda('https://exemplo.com/a.ogg')).toBeNull();
  });

  it('tempo como no app', () => {
    expect(tempoDoAudio(7.9)).toBe('0:07');
    expect(tempoDoAudio(83)).toBe('1:23');
    expect(tempoDoAudio(Infinity)).toBe('0:00');
    expect(tempoDoAudio(NaN)).toBe('0:00');
  });
});
