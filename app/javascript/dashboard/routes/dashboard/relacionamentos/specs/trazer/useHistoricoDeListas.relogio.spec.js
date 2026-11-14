import { effectScope } from 'vue';
import {
  INTERVALO_DO_HISTORICO_MS,
  useHistoricoDeListas,
} from '../../trazer/useHistoricoDeListas';
describe('histórico: um só relógio, resposta velha descartada', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const lista = (id, situacao) => ({ id, situacao, porcentagem: 10 });
  const montar = fonte => {
    const escopo = effectScope();
    const historico = escopo.run(() =>
      useHistoricoDeListas({ fonte, avisar: vi.fn() })
    );
    return { historico, parar: () => escopo.stop() };
  };
  const fonteDeFila = () => {
    const respostas = [];
    return {
      respostas,
      historico: vi.fn(
        () =>
          new Promise(resolve => {
            respostas.push(resolve);
          })
      ),
    };
  };

  it('duas cargas ao mesmo tempo deixam um único temporizador', async () => {
    const fonte = fonteDeFila();
    const { historico } = montar(fonte);
    const a = historico.carregar();
    const b = historico.carregar({ silencioso: true });
    fonte.respostas[0]([lista('x', 'trazendo')]);
    fonte.respostas[1]([lista('x', 'trazendo')]);
    await Promise.all([a, b]);
    expect(vi.getTimerCount()).toBe(1);
  });

  it('a resposta velha não sobrescreve a nova', async () => {
    const fonte = fonteDeFila();
    const { historico } = montar(fonte);
    const velha = historico.carregar();
    const nova = historico.carregar({ silencioso: true });
    fonte.respostas[1]([lista('novo', 'pronto')]);
    await nova;
    fonte.respostas[0]([lista('velho', 'trazendo')]);
    await velha;
    expect(historico.listas.value.map(l => l.id)).toEqual(['novo']);
    expect(historico.carregando.value).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('depois de sair da tela, carregar não pede nada', async () => {
    const fonte = fonteDeFila();
    const { historico, parar } = montar(fonte);
    parar();
    await historico.carregar();
    expect(fonte.historico).not.toHaveBeenCalled();
  });

  it('resposta que chega depois de sair não agenda nada', async () => {
    const fonte = fonteDeFila();
    const { historico, parar } = montar(fonte);
    const carga = historico.carregar();
    parar();
    fonte.respostas[0]([lista('x', 'trazendo')]);
    await carga;
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS * 3);
    expect(fonte.historico).toHaveBeenCalledTimes(1);
  });
});
