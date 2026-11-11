import { effectScope } from 'vue';
import { PRAZO } from '../../trazer/prazo';
import {
  INTERVALO_DO_HISTORICO_MS,
  useHistoricoDeListas,
} from '../../trazer/useHistoricoDeListas';

// O histórico "O que eu já trouxe" e o desfazer (#2894), com fonte falsa.
const AGORA = Date.UTC(2026, 11, 1);
const DIA = 24 * 60 * 60 * 1000;

const lista = (id, situacao, extra = {}) => ({
  id,
  arquivo: `${id}.xlsx`,
  quando: AGORA - 3 * DIA,
  quem: 'Marina Dornelaz',
  total: 195,
  situacao,
  porcentagem: 100,
  ...extra,
});

const montar = fonteParcial => {
  const escopo = effectScope();
  const avisar = vi.fn();
  const fonte = {
    historico: vi.fn(async () => []),
    previaDoDesfazer: vi.fn(async () => ({
      tira: 180,
      devolve: 15,
      receberamCampanha: 3,
    })),
    desfazer: vi.fn(async () => ({})),
    ...fonteParcial,
  };
  const historico = escopo.run(() =>
    useHistoricoDeListas({ fonte, avisar, agora: () => AGORA })
  );
  return { historico, fonte, avisar, parar: () => escopo.stop() };
};

describe('carregar', () => {
  it('guarda as listas e desliga o carregando', async () => {
    const listas = [lista('a', 'pronto')];
    const { historico } = montar({ historico: vi.fn(async () => listas) });
    const carga = historico.carregar();
    expect(historico.carregando.value).toBe(true);
    await carga;
    expect(historico.carregando.value).toBe(false);
    expect(historico.listas.value).toEqual(listas);
    expect(historico.erro.value).toBe(false);
  });

  it('marca erro quando a fonte falha', async () => {
    const { historico } = montar({
      historico: vi.fn(async () => {
        throw new Error('falhou');
      }),
    });
    await historico.carregar();
    expect(historico.erro.value).toBe(true);
    expect(historico.carregando.value).toBe(false);
  });

  it('histórico vazio fica como lista vazia, sem erro', async () => {
    const { historico } = montar();
    await historico.carregar();
    expect(historico.listas.value).toEqual([]);
    expect(historico.erro.value).toBe(false);
  });
});

describe('lista sendo trazida', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('pergunta de novo a cada 1,5 s até ficar pronta, sem piscar o esqueleto', async () => {
    const historicoDaFonte = vi
      .fn()
      .mockResolvedValueOnce([lista('a', 'trazendo', { porcentagem: 40 })])
      .mockResolvedValueOnce([lista('a', 'trazendo', { porcentagem: 80 })])
      .mockResolvedValue([lista('a', 'pronto')]);
    const { historico } = montar({ historico: historicoDaFonte });
    await historico.carregar();
    expect(historico.listas.value[0].porcentagem).toBe(40);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS);
    expect(historico.listas.value[0].porcentagem).toBe(80);
    expect(historico.carregando.value).toBe(false);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS);
    expect(historico.listas.value[0].situacao).toBe('pronto');
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS * 3);
    expect(historicoDaFonte).toHaveBeenCalledTimes(3);
  });

  it('para de perguntar quando a tela sai', async () => {
    const historicoDaFonte = vi.fn(async () => [lista('a', 'trazendo')]);
    const { historico, parar } = montar({ historico: historicoDaFonte });
    await historico.carregar();
    parar();
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS * 3);
    expect(historicoDaFonte).toHaveBeenCalledTimes(1);
  });
});

describe('prazo', () => {
  it('diz se o prazo da lista está aberto ou acabou', () => {
    const { historico } = montar();
    expect(historico.prazoDe(lista('a', 'pronto'))).toBe(PRAZO.ABERTO);
    expect(
      historico.prazoDe(lista('b', 'pronto', { quando: AGORA - 8 * DIA }))
    ).toBe(PRAZO.ACABOU);
    expect(historico.prazoDe(lista('c', 'desfeito'))).toBe(PRAZO.NAO_SE_APLICA);
  });
});

describe('desfazer', () => {
  it('abre mostrando antes o que sai', async () => {
    const { historico } = montar();
    const alvo = lista('a', 'pronto');
    await historico.abrirDesfazer(alvo);
    expect(historico.alvo.value).toEqual(alvo);
    expect(historico.previa.value).toEqual({
      tira: 180,
      devolve: 15,
      receberamCampanha: 3,
    });
  });

  it('erro na prévia fica marcado', async () => {
    const { historico } = montar({
      previaDoDesfazer: vi.fn(async () => {
        throw new Error('falhou');
      }),
    });
    await historico.abrirDesfazer(lista('a', 'pronto'));
    expect(historico.previaComErro.value).toBe(true);
    expect(historico.previa.value).toBeNull();
  });

  it('confirmar desfaz, recarrega o histórico e devolve true', async () => {
    const historicoDaFonte = vi
      .fn()
      .mockResolvedValueOnce([lista('a', 'pronto')])
      .mockResolvedValue([lista('a', 'desfeito')]);
    const { historico, fonte } = montar({ historico: historicoDaFonte });
    await historico.carregar();
    await historico.abrirDesfazer(historico.listas.value[0]);
    expect(await historico.confirmarDesfazer()).toBe(true);
    expect(fonte.desfazer).toHaveBeenCalledWith('a');
    expect(historico.listas.value[0].situacao).toBe('desfeito');
    expect(historico.desfazendo.value).toBe(false);
  });

  it('erro ao desfazer avisa e devolve false', async () => {
    const { historico, avisar } = montar({
      desfazer: vi.fn(async () => {
        throw new Error('falhou');
      }),
    });
    await historico.abrirDesfazer(lista('a', 'pronto'));
    expect(await historico.confirmarDesfazer()).toBe(false);
    expect(avisar).toHaveBeenCalledWith(
      'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER'
    );
    expect(historico.desfazendo.value).toBe(false);
  });

  it('sem lista escolhida, confirmar não faz nada', async () => {
    const { historico, fonte } = montar();
    expect(await historico.confirmarDesfazer()).toBe(false);
    expect(fonte.desfazer).not.toHaveBeenCalled();
  });

  it('fechar limpa a escolha', async () => {
    const { historico } = montar();
    await historico.abrirDesfazer(lista('a', 'pronto'));
    historico.fecharDesfazer();
    expect(historico.alvo.value).toBeNull();
    expect(historico.previa.value).toBeNull();
  });
});
