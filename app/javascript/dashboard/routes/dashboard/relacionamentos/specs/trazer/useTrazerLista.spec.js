import { effectScope } from 'vue';
import { trazerFonte, esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
import { ETAPAS } from '../../trazer/etapas';
import {
  ERROS,
  INTERVALO_DO_ANDAMENTO_MS,
  useTrazerLista,
} from '../../trazer/useTrazerLista';

// O estado de "Trazer minha lista" (#2894), com a fonte de demonstração e relógio falso.
const carregarDemo = () => import('../../demo/trazer.js');
const planilha = nome => ({ name: nome });

const montar = (opcoes = {}) => {
  const escopo = effectScope();
  const avisar = vi.fn();
  const aoFalhar = vi.fn();
  const fonte =
    opcoes.fonte ||
    trazerFonte({ demo: 'cheio', carregarDemo, atraso: 0, atrasoDaLeitura: 0 });
  const tela = escopo.run(() => useTrazerLista({ fonte, avisar, aoFalhar }));
  return { tela, avisar, aoFalhar, fonte, parar: () => escopo.stop() };
};

const erroDeNome = nome => Object.assign(new Error(nome), { name: nome });
const LIDA = { id: 'l1', arquivo: 'a.csv', perguntas: [], problemas: [] };

const lerExemplo = async tela => {
  await tela.usarExemplo();
  return tela;
};

const responderTudo = tela => {
  tela.responder('clientes', 'sim_todas');
  tela.responder('telefone', 'da_pessoa');
};

beforeEach(() => esquecerMemoriaDaDemo());

describe('Enviar', () => {
  it('arquivo que não é planilha dá o erro de tipo e não lê', async () => {
    const { tela, fonte } = montar();
    const ler = vi.spyOn(fonte, 'ler');
    await tela.escolherArquivo(planilha('foto.png'));
    expect(tela.erro.value).toBe(ERROS.TIPO);
    expect(ler).not.toHaveBeenCalled();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
  });

  it('planilha boa vai para as perguntas quando a leitura pede', async () => {
    const { tela } = montar();
    await tela.escolherArquivo(planilha('lista.xlsx'));
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('clientes');
    expect(tela.leitura.value.arquivo).toBe('lista.xlsx');
  });

  it('mostra "lendo" enquanto a fonte trabalha', async () => {
    let terminar;
    const fonte = {
      ler: () =>
        new Promise(resolve => {
          terminar = () =>
            resolve({
              id: 'l1',
              arquivo: 'a.csv',
              perguntas: [],
              problemas: [],
            });
        }),
    };
    const { tela } = montar({ fonte });
    const lendo = tela.escolherArquivo(planilha('a.csv'));
    expect(tela.lendo.value).toBe(true);
    terminar();
    await lendo;
    expect(tela.lendo.value).toBe(false);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('erro de leitura aparece e "tentar de novo" lê o mesmo arquivo', async () => {
    const ler = vi
      .fn()
      .mockRejectedValueOnce(new Error('falhou'))
      .mockResolvedValueOnce({
        id: 'l1',
        arquivo: 'a.csv',
        perguntas: [],
        problemas: [],
      });
    const { tela } = montar({ fonte: { ler } });
    await tela.escolherArquivo(planilha('a.csv'));
    expect(tela.erro.value).toBe(ERROS.LEITURA);
    expect(tela.lendo.value).toBe(false);
    await tela.tentarDeNovo();
    expect(ler).toHaveBeenCalledTimes(2);
    expect(ler.mock.calls[1][0]).toEqual(planilha('a.csv'));
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  // #2896 — o Excel antigo saiu: a tela recusa antes de mandar ao servidor.
  it('.xls dá o erro de tipo e não lê', async () => {
    const ler = vi.fn();
    const { tela } = montar({ fonte: { ler } });
    await tela.escolherArquivo(planilha('lista.xls'));
    expect(tela.erro.value).toBe(ERROS.TIPO);
    expect(ler).not.toHaveBeenCalled();
  });

  it.each([
    ['PLANILHA_TIPO', ERROS.TIPO],
    ['PLANILHA_GRANDE', ERROS.GRANDE],
    ['PLANILHA_VAZIA', ERROS.VAZIA],
    ['PLANILHA_SEM_CONTATO', ERROS.SEM_CONTATO],
    ['LEITURA_PENDENTE', ERROS.DEMOROU],
    ['LEITURA_FALHOU', ERROS.LEITURA],
  ])('a recusa %s do servidor vira o erro "%s"', async (nome, erro) => {
    const ler = vi.fn().mockRejectedValue(erroDeNome(nome));
    const { tela } = montar({ fonte: { ler } });
    await tela.escolherArquivo(planilha('a.csv'));
    expect(tela.erro.value).toBe(erro);
    expect(tela.semAcesso.value).toBe(false);
  });
});

// #2896 — quem não pode trazer lista: o servidor recusa (401 ou 403), a fonte dá
// o nome SEM_ACESSO e a tela para de oferecer "tentar de novo".
describe('sem acesso', () => {
  const SEM_ACESSO = erroDeNome('SEM_ACESSO');

  it('na leitura: liga `semAcesso` e não mostra erro de leitura', async () => {
    const { tela } = montar({
      fonte: { ler: vi.fn().mockRejectedValue(SEM_ACESSO) },
    });
    expect(tela.semAcesso.value).toBe(false);
    await tela.escolherArquivo(planilha('a.csv'));
    expect(tela.semAcesso.value).toBe(true);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.lendo.value).toBe(false);
  });

  it('numa escrita: liga `semAcesso` sem o aviso de "tente de novo"', async () => {
    const { tela, avisar } = montar({
      fonte: {
        ler: async () => LIDA,
        trocarDestino: vi.fn().mockRejectedValue(SEM_ACESSO),
      },
    });
    await tela.escolherArquivo(planilha('a.csv'));
    await tela.trocarDestino('Cel', 'nao_guardar');
    expect(tela.semAcesso.value).toBe(true);
    expect(avisar).not.toHaveBeenCalled();
    expect(tela.ocupado.value).toBe(false);
  });

  it('ao trazer: liga `semAcesso` e não mostra o erro de trazer', async () => {
    const { tela } = montar({
      fonte: {
        ler: async () => LIDA,
        trazer: vi.fn().mockRejectedValue(SEM_ACESSO),
      },
    });
    await tela.escolherArquivo(planilha('a.csv'));
    await tela.trazer();
    expect(tela.semAcesso.value).toBe(true);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('no andamento: liga `semAcesso` e não mostra o erro do andamento', async () => {
    const { tela } = montar({
      fonte: {
        ler: async () => LIDA,
        trazer: async () => ({ trazidaId: 't1' }),
        andamento: vi.fn().mockRejectedValue(SEM_ACESSO),
      },
    });
    await tela.escolherArquivo(planilha('a.csv'));
    await tela.trazer();
    expect(tela.semAcesso.value).toBe(true);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
  });
});

describe('Perguntas', () => {
  it('Continuar só vale depois de escolher', async () => {
    const { tela } = montar();
    await lerExemplo(tela);
    expect(tela.podeContinuar.value).toBe(false);
    tela.responder('clientes', 'sim_todas');
    expect(tela.podeContinuar.value).toBe(true);
  });

  it('"Algumas" pede a coluna e "Sim, todas" apaga a coluna escolhida', async () => {
    const { tela } = montar();
    await lerExemplo(tela);
    tela.responder('clientes', 'algumas');
    expect(tela.podeContinuar.value).toBe(false);
    tela.escolherColunaDeCliente('Situação');
    expect(tela.podeContinuar.value).toBe(true);
    tela.responder('clientes', 'sim_todas');
    expect(tela.respostas.value.colunaCliente).toBeUndefined();
  });

  it('anda pergunta por pergunta e grava as respostas na última', async () => {
    const { tela, fonte } = montar();
    const responder = vi.spyOn(fonte, 'responder');
    await lerExemplo(tela);
    tela.responder('clientes', 'ainda_nao');
    await tela.continuar();
    expect(tela.perguntaAtual.value.id).toBe('telefone');
    expect(responder).not.toHaveBeenCalled();
    expect(tela.podeContinuar.value).toBe(false);
    tela.responder('telefone', 'nao_usar');
    await tela.continuar();
    expect(responder).toHaveBeenCalledWith(tela.leitura.value.id, {
      clientes: 'ainda_nao',
      telefone: 'nao_usar',
    });
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.leitura.value.colunas.find(c => c.nome === 'Cel').destino).toBe(
      'nao_guardar'
    );
  });

  it('Voltar mantém as respostas', async () => {
    const { tela } = montar();
    await lerExemplo(tela);
    tela.responder('clientes', 'ainda_nao');
    await tela.continuar();
    tela.voltar();
    expect(tela.perguntaAtual.value.id).toBe('clientes');
    expect(tela.respostas.value.clientes).toBe('ainda_nao');
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
  });

  it('erro ao gravar as respostas avisa e fica na pergunta', async () => {
    const { tela, fonte, avisar } = montar();
    await lerExemplo(tela);
    tela.responder('clientes', 'ainda_nao');
    await tela.continuar();
    tela.responder('telefone', 'da_pessoa');
    vi.spyOn(fonte, 'responder').mockRejectedValue(new Error('falhou'));
    await tela.continuar();
    expect(avisar).toHaveBeenCalledWith('RELACIONAMENTOS_TRAZER.ERROS.GUARDAR');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
  });
});

describe('Conferir', () => {
  const chegarEmConferir = async () => {
    const montado = montar();
    await lerExemplo(montado.tela);
    responderTudo(montado.tela);
    await montado.tela.continuar();
    await montado.tela.continuar();
    return montado;
  };

  it('começa em 195 com 8 linhas que precisam de você', async () => {
    const { tela } = await chegarEmConferir();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.entram.value).toBe(195);
    expect(tela.resumo.value.precisamDeVoce).toBe(8);
  });

  // Quantas entram é a conta da fonte (o servidor; aqui, a demonstração). A
  // tela não chama de "nova" a linha consertada.
  it('guardar a linha muda quantas entram e quem precisa de você na hora', async () => {
    const { tela } = await chegarEmConferir();
    await tela.guardar(14, '+5511973800014');
    expect(tela.entram.value).toBe(196);
    expect(tela.resumo.value).toMatchObject({ novas: 180, precisamDeVoce: 7 });
  });

  it('deixar de fora tira a linha dos que precisam de você sem somar', async () => {
    const { tela } = await chegarEmConferir();
    await tela.deixarDeFora(62);
    expect(tela.entram.value).toBe(195);
    expect(tela.resumo.value).toMatchObject({ precisamDeVoce: 7, deixadas: 1 });
  });

  // A coluna vai pela posição dela na planilha, como a tela manda ao servidor.
  it('trocar o destino de uma coluna vai para a leitura', async () => {
    const { tela } = await chegarEmConferir();
    const { indice } = tela.leitura.value.colunas.find(
      c => c.nome === 'Aniversário'
    );
    await tela.trocarDestino(indice, 'nao_guardar');
    expect(
      tela.leitura.value.colunas.find(c => c.nome === 'Aniversário').destino
    ).toBe('nao_guardar');
  });

  it('erro de escrita na linha fica com a linha (sem toast) e mantém a leitura', async () => {
    const { tela, fonte, avisar } = await chegarEmConferir();
    vi.spyOn(fonte, 'consertar').mockRejectedValue(new Error('falhou'));
    expect(await tela.guardar(14, 'x')).toBe(false);
    expect(avisar).not.toHaveBeenCalled();
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 14,
      motivo: 'nao_salvou',
    });
    expect(tela.entram.value).toBe(195);
    expect(tela.ocupado.value).toBe(false);
  });
});

describe('Trazendo e Pronto', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const andamentoFalso = situacoes => {
    const fila = [...situacoes];
    return {
      ler: async () => ({
        id: 'l1',
        arquivo: 'a.csv',
        perguntas: [],
        problemas: [],
        resumo: { novas: 3, completadas: 0 },
      }),
      trazer: vi.fn(async () => ({ trazidaId: 't1' })),
      andamento: vi.fn(async () => fila.shift() || fila.at(-1)),
    };
  };

  // A espera cresce a cada consulta (1,5 s, depois 2,25 s…).
  it('consulta de novo sozinha até terminar e vai para Pronto com as contas da lista', async () => {
    const fonte = andamentoFalso([
      { porcentagem: 0, situacao: 'trazendo', novas: 0, completadas: 0 },
      { porcentagem: 40, situacao: 'trazendo', novas: 1, completadas: 0 },
      { porcentagem: 100, situacao: 'pronto', novas: 2, completadas: 1 },
    ]);
    const { tela } = montar({ fonte });
    await tela.usarExemplo();
    await tela.trazer();
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    expect(tela.porcentagem.value).toBe(0);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS);
    expect(tela.porcentagem.value).toBe(40);
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS);
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS / 2);
    expect(tela.etapa.value).toBe(ETAPAS.PRONTO);
    expect(tela.novasTrazidas.value).toBe(2);
    expect(tela.completadasTrazidas.value).toBe(1);
    expect(fonte.andamento).toHaveBeenCalledTimes(3);
  });

  it('para de consultar quando a tela sai', async () => {
    const fonte = andamentoFalso([
      { porcentagem: 10, situacao: 'trazendo', total: 3 },
    ]);
    const { tela, parar } = montar({ fonte });
    await tela.usarExemplo();
    await tela.trazer();
    parar();
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS * 4);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
  });

  it('erro ao trazer fica em conferir e tentar de novo traz', async () => {
    const fonte = andamentoFalso([
      { porcentagem: 100, situacao: 'pronto', total: 3 },
    ]);
    fonte.trazer
      .mockRejectedValueOnce(new Error('falhou'))
      .mockResolvedValueOnce({ trazidaId: 't1' });
    const { tela } = montar({ fonte });
    await tela.usarExemplo();
    await tela.trazer();
    expect(tela.erro.value).toBe(ERROS.TRAZER);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.ocupado.value).toBe(false);
    await tela.tentarDeNovo();
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.etapa.value).toBe(ETAPAS.PRONTO);
  });

  it('erro no andamento mostra o erro e tentar de novo continua', async () => {
    const fonte = andamentoFalso([
      { porcentagem: 100, situacao: 'pronto', total: 3 },
    ]);
    fonte.andamento
      .mockRejectedValueOnce(new Error('falhou'))
      .mockResolvedValueOnce({
        porcentagem: 100,
        situacao: 'pronto',
        total: 3,
      });
    const { tela } = montar({ fonte });
    await tela.usarExemplo();
    await tela.trazer();
    expect(tela.erro.value).toBe(ERROS.ANDAMENTO);
    await tela.tentarDeNovo();
    expect(tela.etapa.value).toBe(ETAPAS.PRONTO);
  });

  // #2896 — a lista que parou no meio não é "Pronto": a tela avisa e chama
  // `aoFalhar` (a página volta ao começo, onde o histórico tem o "Tentar de novo").
  it('lista que falhou no meio avisa, chama `aoFalhar` e não vai para Pronto', async () => {
    const fonte = andamentoFalso([
      { porcentagem: 10, situacao: 'trazendo', total: 3 },
      { porcentagem: 40, situacao: 'falhou', total: 3 },
    ]);
    const { tela, avisar, aoFalhar } = montar({ fonte });
    await tela.usarExemplo();
    await tela.trazer();
    expect(aoFalhar).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS);
    expect(aoFalhar).toHaveBeenCalledTimes(1);
    expect(avisar).toHaveBeenCalledWith('RELACIONAMENTOS_TRAZER.ERROS.TRAZER');
    expect(tela.etapa.value).not.toBe(ETAPAS.PRONTO);
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS * 3);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
  });

  it('ao sair, avisa a fonte para parar o que estiver esperando', async () => {
    const fonte = { ...andamentoFalso([]), encerrar: vi.fn() };
    const { parar } = montar({ fonte });
    expect(fonte.encerrar).not.toHaveBeenCalled();
    parar();
    expect(fonte.encerrar).toHaveBeenCalledTimes(1);
  });

  it('"Trazer outra lista" recomeça limpo', async () => {
    const fonte = andamentoFalso([
      { porcentagem: 100, situacao: 'pronto', total: 3 },
    ]);
    const { tela } = montar({ fonte });
    await tela.usarExemplo();
    await tela.trazer();
    tela.recomecar();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.leitura.value).toBeNull();
    expect(tela.respostas.value).toEqual({});
    expect(tela.erro.value).toBe(ERROS.NENHUM);
  });
});
