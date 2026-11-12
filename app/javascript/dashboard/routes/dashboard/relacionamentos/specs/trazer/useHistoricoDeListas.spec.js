import { effectScope } from 'vue';
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
      ficam: 18,
    })),
    desfazer: vi.fn(async () => ({})),
    tentarDeNovo: vi.fn(async () => ({})),
    ...fonteParcial,
  };
  const historico = escopo.run(() => useHistoricoDeListas({ fonte, avisar }));
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

  // #2896 — quem não pode trazer lista não recebe "tentar de novo".
  it('recusa por falta de acesso liga `semAcesso`, não o erro', async () => {
    const { historico } = montar({
      historico: vi.fn(async () => {
        throw Object.assign(new Error('403'), { name: 'SEM_ACESSO' });
      }),
    });
    expect(historico.semAcesso.value).toBe(false);
    await historico.carregar();
    expect(historico.semAcesso.value).toBe(true);
    expect(historico.erro.value).toBe(false);
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

  // A espera cresce a cada pergunta (1,5 s, depois 2,25 s…): consultaComRecuo.spec.js.
  it('pergunta de novo sozinha, com a espera crescendo, até ficar pronta, sem piscar o esqueleto', async () => {
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
    expect(historico.listas.value[0].situacao).toBe('trazendo');
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS / 2);
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

// #2896 — o servidor desfaz depois do pedido: a lista fica `desfazendo` e a
// tela acompanha do mesmo jeito que acompanha a lista sendo trazida.
describe('lista sendo desfeita', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('pergunta de novo sozinha até a lista ficar desfeita, e aí para', async () => {
    const historicoDaFonte = vi
      .fn()
      .mockResolvedValueOnce([lista('a', 'desfazendo')])
      .mockResolvedValueOnce([lista('a', 'desfazendo')])
      .mockResolvedValue([lista('a', 'desfeito')]);
    const { historico, avisar } = montar({ historico: historicoDaFonte });
    await historico.carregar();
    expect(historico.listas.value[0].situacao).toBe('desfazendo');
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS);
    expect(historico.listas.value[0].situacao).toBe('desfazendo');
    expect(historico.carregando.value).toBe(false);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS * 1.5);
    expect(historico.listas.value[0].situacao).toBe('desfeito');
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS * 3);
    expect(historicoDaFonte).toHaveBeenCalledTimes(3);
    expect(avisar).not.toHaveBeenCalled();
  });

  // O desfazer que quebra no servidor devolve a lista ao que era: a tela diz
  // que não deu, em vez de a linha só voltar, calada.
  it.each(['pronto', 'falhou'])(
    'a lista que volta de "desfazendo" para "%s" não foi desfeita: avisa uma vez',
    async voltou => {
      const historicoDaFonte = vi
        .fn()
        .mockResolvedValueOnce([lista('a', 'desfazendo'), lista('b', 'pronto')])
        .mockResolvedValue([lista('a', voltou), lista('b', 'pronto')]);
      const { historico, avisar } = montar({ historico: historicoDaFonte });
      await historico.carregar();
      expect(avisar).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS);
      expect(historico.listas.value[0].situacao).toBe(voltou);
      await historico.carregar({ silencioso: true });
      expect(avisar).toHaveBeenCalledTimes(1);
      expect(avisar).toHaveBeenCalledWith(
        'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER'
      );
    }
  );
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
      ficam: 18,
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

  // #2896 — a lista que o servidor ainda não deixa desfazer (ela não foi
  // trazida até o fim): não é erro de "tente de novo"; a tela diz por quê.
  describe('a lista que ainda não dá para desfazer', () => {
    const recusa = () =>
      vi.fn(async () => {
        throw Object.assign(new Error('422'), { name: 'NAO_PODE_DESFAZER' });
      });

    it('recusada ao confirmar: liga `naoPodeDesfazer`, sem aviso, e mostra a lista como está agora', async () => {
      const historicoDaFonte = vi
        .fn()
        .mockResolvedValueOnce([lista('a', 'pronto')])
        .mockResolvedValue([lista('a', 'falhou')]);
      const { historico, avisar } = montar({
        historico: historicoDaFonte,
        desfazer: recusa(),
      });
      await historico.carregar();
      await historico.abrirDesfazer(historico.listas.value[0]);
      expect(historico.naoPodeDesfazer.value).toBe(false);
      expect(await historico.confirmarDesfazer()).toBe(false);
      expect(historico.naoPodeDesfazer.value).toBe(true);
      expect(avisar).not.toHaveBeenCalled();
      expect(historico.desfazendo.value).toBe(false);
      expect(historico.listas.value[0].situacao).toBe('falhou');
      expect(historico.carregando.value).toBe(false);
    });

    it('recusada já na prévia: liga `naoPodeDesfazer`, não o erro da prévia', async () => {
      const { historico } = montar({ previaDoDesfazer: recusa() });
      await historico.abrirDesfazer(lista('a', 'pronto'));
      expect(historico.naoPodeDesfazer.value).toBe(true);
      expect(historico.previaComErro.value).toBe(false);
      expect(historico.previa.value).toBeNull();
    });

    it('depois da recusa, confirmar não pede de novo', async () => {
      const { historico, fonte } = montar({ previaDoDesfazer: recusa() });
      await historico.abrirDesfazer(lista('a', 'pronto'));
      expect(await historico.confirmarDesfazer()).toBe(false);
      expect(fonte.desfazer).not.toHaveBeenCalled();
    });

    it('fechar, ou abrir outra lista, apaga a recusa', async () => {
      const previaDoDesfazer = recusa();
      const { historico } = montar({ previaDoDesfazer });
      await historico.abrirDesfazer(lista('a', 'pronto'));
      historico.fecharDesfazer();
      expect(historico.naoPodeDesfazer.value).toBe(false);
      await historico.abrirDesfazer(lista('a', 'pronto'));
      expect(historico.naoPodeDesfazer.value).toBe(true);
      previaDoDesfazer.mockResolvedValueOnce({ tira: 1, ficam: 0, devolve: 0 });
      await historico.abrirDesfazer(lista('b', 'pronto'));
      expect(historico.naoPodeDesfazer.value).toBe(false);
    });
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

// #2896 — a lista que parou no meio: "Tentar de novo" continua de onde parou.
describe('tentar de novo', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const falhou = lista('a', 'falhou', { podeTentar: true, porcentagem: 40 });

  it('pede à fonte, recarrega e volta a perguntar enquanto a lista é trazida', async () => {
    const historicoDaFonte = vi
      .fn()
      .mockResolvedValueOnce([falhou])
      .mockResolvedValueOnce([lista('a', 'trazendo', { porcentagem: 40 })])
      .mockResolvedValue([lista('a', 'pronto')]);
    const { historico, fonte } = montar({ historico: historicoDaFonte });
    await historico.carregar();
    expect(await historico.tentarDeNovo(falhou)).toBe(true);
    expect(fonte.tentarDeNovo).toHaveBeenCalledWith('a');
    expect(historico.listas.value[0].situacao).toBe('trazendo');
    expect(historico.carregando.value).toBe(false);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS);
    expect(historico.listas.value[0].situacao).toBe('pronto');
  });

  it('enquanto tenta, diz qual lista e ignora o segundo clique', async () => {
    let terminar;
    const tentarDeNovo = vi.fn(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const { historico } = montar({ tentarDeNovo });
    const primeira = historico.tentarDeNovo(falhou);
    expect(historico.tentando.value).toBe('a');
    expect(await historico.tentarDeNovo(falhou)).toBe(false);
    terminar({});
    await primeira;
    expect(tentarDeNovo).toHaveBeenCalledTimes(1);
    expect(historico.tentando.value).toBeNull();
  });

  it('erro ao tentar avisa e devolve false', async () => {
    const { historico, avisar } = montar({
      tentarDeNovo: vi.fn(async () => {
        throw new Error('falhou');
      }),
    });
    expect(await historico.tentarDeNovo(falhou)).toBe(false);
    expect(avisar).toHaveBeenCalledWith('RELACIONAMENTOS_TRAZER.ERROS.TRAZER');
    expect(historico.tentando.value).toBeNull();
  });

  it('recusa por falta de acesso liga `semAcesso`, sem aviso', async () => {
    const { historico, avisar } = montar({
      tentarDeNovo: vi.fn(async () => {
        throw Object.assign(new Error('403'), { name: 'SEM_ACESSO' });
      }),
    });
    expect(await historico.tentarDeNovo(falhou)).toBe(false);
    expect(historico.semAcesso.value).toBe(true);
    expect(avisar).not.toHaveBeenCalled();
  });
});
