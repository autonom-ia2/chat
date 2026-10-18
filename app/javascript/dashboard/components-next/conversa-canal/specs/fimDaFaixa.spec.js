// A faixa de não lidas some depois de lida (pedido do Rodrigo, 18/10): 5 s com a aba
// visível. Aba escondida não conta o tempo; sair e voltar continua de onde parou.
import {
  TEMPO_DA_FAIXA_EM_MS,
  agendarFimDaFaixa,
  faixaDispensada,
} from '../rolagemDaPele';

const visibilidade = estado =>
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => estado,
  });

describe('fim da faixa de não lidas', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    visibilidade('visible');
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('some depois do tempo com a aba visível', () => {
    const aoFim = vi.fn();
    agendarFimDaFaixa(aoFim);
    vi.advanceTimersByTime(TEMPO_DA_FAIXA_EM_MS - 1);
    expect(aoFim).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(aoFim).toHaveBeenCalledTimes(1);
  });

  it('com a aba escondida só começa a contar quando ela volta', () => {
    visibilidade('hidden');
    const aoFim = vi.fn();
    agendarFimDaFaixa(aoFim);
    vi.advanceTimersByTime(TEMPO_DA_FAIXA_EM_MS * 3);
    expect(aoFim).not.toHaveBeenCalled();
    visibilidade('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    vi.advanceTimersByTime(TEMPO_DA_FAIXA_EM_MS);
    expect(aoFim).toHaveBeenCalledTimes(1);
  });

  it('sair da aba no meio pausa; voltar continua de onde parou', () => {
    const aoFim = vi.fn();
    agendarFimDaFaixa(aoFim);
    vi.advanceTimersByTime(2000);
    visibilidade('hidden');
    document.dispatchEvent(new Event('visibilitychange'));
    vi.advanceTimersByTime(60000);
    expect(aoFim).not.toHaveBeenCalled();
    visibilidade('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    vi.advanceTimersByTime(TEMPO_DA_FAIXA_EM_MS - 2000 - 1);
    expect(aoFim).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(aoFim).toHaveBeenCalledTimes(1);
  });

  it('cancelar (trocou de conversa) não deixa a faixa sumir depois', () => {
    const aoFim = vi.fn();
    const cancelar = agendarFimDaFaixa(aoFim);
    cancelar();
    vi.advanceTimersByTime(TEMPO_DA_FAIXA_EM_MS * 2);
    expect(aoFim).not.toHaveBeenCalled();
  });

  it('dispensada perde a 1ª não lida, guarda o número e marca que abriu na faixa', () => {
    const marco = {
      conversaId: 7,
      pronta: true,
      primeiraNaoLida: 31,
      quantidade: 2,
    };
    expect(faixaDispensada(marco)).toEqual({
      conversaId: 7,
      pronta: true,
      primeiraNaoLida: null,
      quantidade: 2,
      dispensada: true,
    });
  });
});
