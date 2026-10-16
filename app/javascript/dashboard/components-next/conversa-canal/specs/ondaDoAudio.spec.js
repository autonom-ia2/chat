import {
  BARRAS,
  NIVEIS,
  barrasDoAudio,
  carregarOnda,
  tempoDoAudio,
} from '../audio/ondaDoAudio';

describe('onda do áudio (#1702)', () => {
  it('uma barra por trecho, do silêncio ao pico, normalizada pelo maior', () => {
    const amostras = Float32Array.from({ length: 360 }, (_, i) =>
      i < 180 ? 0.1 : -0.5
    );
    const barras = barrasDoAudio(amostras);
    expect(barras).toHaveLength(BARRAS);
    expect(barras[0]).toBe(Math.round((0.1 / 0.5) * (NIVEIS - 1)));
    expect(barras[BARRAS - 1]).toBe(NIVEIS - 1);
    expect(Math.max(...barras)).toBeLessThan(NIVEIS);
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
