import { flushPromises } from '@vue/test-utils';
import Decoder from 'wavesurfer.js/dist/decoder.js';
import {
  BARRAS,
  NIVEIS,
  SIMULTANEAS,
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

  it('a onda do mesmo endereço não baixa o arquivo de novo', async () => {
    const decode = vi.spyOn(Decoder, 'decode').mockResolvedValue({
      getChannelData: () => new Float32Array(10),
      duration: 3,
    });
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)),
    });
    const url = 'https://exemplo.com/guardada.ogg';
    const primeira = await carregarOnda(url);
    const segunda = await carregarOnda(url);
    expect(segunda).toBe(primeira);
    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    decode.mockRestore();
  });

  it('com a chave estável, o endereço com carimbo novo não baixa de novo (#2113)', async () => {
    const decode = vi.spyOn(Decoder, 'decode').mockResolvedValue({
      getChannelData: () => new Float32Array(10),
      duration: 3,
    });
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)),
    });
    const chave = 'https://exemplo.com/carimbada.ogg';
    const primeira = await carregarOnda(`${chave}?t=1`, { chave });
    const segunda = await carregarOnda(`${chave}?t=2`, { chave });
    expect(segunda).toBe(primeira);
    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    expect(globalThis.fetch.mock.calls[0][0]).toBe(`${chave}?t=1`);
    decode.mockRestore();
  });

  it(`no máximo ${SIMULTANEAS} áudios baixando ao mesmo tempo; os outros esperam`, async () => {
    const decode = vi.spyOn(Decoder, 'decode').mockResolvedValue({
      getChannelData: () => new Float32Array(10),
      duration: 3,
    });
    const respostas = [];
    globalThis.fetch = vi.fn(
      () =>
        new Promise(resolve => {
          respostas.push(() =>
            resolve({
              ok: true,
              arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)),
            })
          );
        })
    );
    const pedidos = [1, 2, 3, 4].map(n =>
      carregarOnda(`https://exemplo.com/fila-${n}.ogg`)
    );
    await flushPromises();
    expect(globalThis.fetch).toHaveBeenCalledTimes(SIMULTANEAS);

    respostas[0]();
    await flushPromises();
    expect(globalThis.fetch).toHaveBeenCalledTimes(SIMULTANEAS + 1);

    respostas.slice(1).forEach(responder => responder());
    await flushPromises();
    respostas.slice(SIMULTANEAS + 1).forEach(responder => responder());
    const ondas = await Promise.all(pedidos);
    expect(ondas.every(onda => onda?.duracao === 3)).toBe(true);
    expect(globalThis.fetch).toHaveBeenCalledTimes(4);
    decode.mockRestore();
  });

  it('quem saiu da tela desiste da fila e não baixa nada', async () => {
    const respostas = [];
    globalThis.fetch = vi.fn(
      () =>
        new Promise(resolve => {
          respostas.push(() => resolve({ ok: false }));
        })
    );
    const ocupando = [1, 2].map(n =>
      carregarOnda(`https://exemplo.com/ocupa-${n}.ogg`)
    );
    const saiu = new AbortController();
    const naFila = carregarOnda('https://exemplo.com/saiu.ogg', {
      signal: saiu.signal,
    });
    await flushPromises();
    saiu.abort();
    expect(await naFila).toBeNull();

    respostas.forEach(responder => responder());
    await Promise.all(ocupando);
    expect(globalThis.fetch).toHaveBeenCalledTimes(2);
    expect(globalThis.fetch).not.toHaveBeenCalledWith(
      'https://exemplo.com/saiu.ogg',
      expect.anything()
    );
  });

  it('signal abortado devolve null mesmo com a onda guardada', async () => {
    const decode = vi.spyOn(Decoder, 'decode').mockResolvedValue({
      getChannelData: () => new Float32Array(10),
      duration: 3,
    });
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)),
    });
    const url = 'https://exemplo.com/guardada-e-abortada.ogg';
    expect(await carregarOnda(url)).not.toBeNull();
    const saiu = new AbortController();
    saiu.abort();
    expect(await carregarOnda(url, { signal: saiu.signal })).toBeNull();
    decode.mockRestore();
  });

  it('tempo como no app', () => {
    expect(tempoDoAudio(7.9)).toBe('0:07');
    expect(tempoDoAudio(83)).toBe('1:23');
    expect(tempoDoAudio(Infinity)).toBe('0:00');
    expect(tempoDoAudio(NaN)).toBe('0:00');
  });
});
