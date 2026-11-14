import { effectScope } from 'vue';
import { ETAPAS } from '../../trazer/etapas';
import {
  INTERVALO_DO_ANDAMENTO_MS,
  useTrazerLista,
} from '../../trazer/useTrazerLista';
describe('relógio do andamento: geração e desmontagem', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const fonteComConsultaEmVoo = () => {
    const respostas = [];
    return {
      respostas,
      ler: async () => ({
        id: 'l1',
        arquivo: 'a.csv',
        perguntas: [],
        problemas: [],
        resumo: { novas: 3, completadas: 0 },
      }),
      trazer: vi.fn(async () => ({ trazidaId: 't1' })),
      andamento: vi.fn(
        () =>
          new Promise(resolve => {
            respostas.push(resolve);
          })
      ),
    };
  };
  const montar = fonte => {
    const escopo = effectScope();
    const tela = escopo.run(() => useTrazerLista({ fonte, avisar: vi.fn() }));
    return { tela, parar: () => escopo.stop() };
  };

  it('recomecar com consulta em voo: a resposta velha não reagenda o relógio', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela } = montar(fonte);
    await tela.usarExemplo();
    const trazendo = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    tela.recomecar();
    fonte.respostas[0]({ porcentagem: 40, situacao: 'trazendo', total: 3 });
    await trazendo;
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS * 3);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    expect(tela.porcentagem.value).toBe(0);
  });

  it('recomecar com consulta em voo: a resposta "pronto" não dispara o término', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela } = montar(fonte);
    await tela.usarExemplo();
    const trazendo = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    tela.recomecar();
    fonte.respostas[0]({ porcentagem: 100, situacao: 'pronto', total: 3 });
    await trazendo;
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.novasTrazidas.value).toBe(0);
  });

  it('um novo trazer depois de recomecar ignora a consulta velha', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela } = montar(fonte);
    await tela.usarExemplo();
    const primeira = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    tela.recomecar();
    await tela.usarExemplo();
    const segunda = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    fonte.respostas[0]({ porcentagem: 100, situacao: 'pronto', total: 99 });
    await primeira;
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    expect(tela.novasTrazidas.value).toBe(0);
    fonte.respostas[1]({ porcentagem: 50, situacao: 'trazendo', total: 3 });
    await segunda;
    expect(tela.porcentagem.value).toBe(50);
  });

  it('desmontar com consulta em voo: nada mais é agendado nem mudado', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela, parar } = montar(fonte);
    await tela.usarExemplo();
    const trazendo = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    parar();
    fonte.respostas[0]({ porcentagem: 40, situacao: 'trazendo', total: 3 });
    await trazendo;
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS * 3);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
  });
});
