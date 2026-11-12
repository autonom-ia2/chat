import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { ETAPAS } from '../../trazer/etapas';
import { ERROS } from '../../trazer/useTrazerLista';
import {
  PERGUNTAS,
  RESPONDIDAS,
  erroDeNome,
  fonteDeMentira,
  lida,
  montarTela,
  noConferir,
} from './apoioDaTela';
import {
  LENDO,
  PLANILHA,
  TETO,
  erroHttp,
  montarFonteReal,
  problema,
  pronta,
  responder,
  semRede,
} from './apoioDoServidor';

// #2896, Fatia 2 — retomar uma leitura que o servidor já tem: só pergunta (GET),
// nunca envia o arquivo de novo. É o que a tela usa depois de recarregar a
// página, depois de uma escrita que fez a planilha ser lida de novo e quando a
// espera pelo envio falhou.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real: retomar', () => {
  it('espera sair de "lendo" e devolve a leitura, sem enviar nada', async () => {
    const { fonte, espera } = montarFonteReal();
    responde('leitura', LENDO, LENDO, pronta());
    const leitura = await fonte.retomar(812);
    expect(TrazerAPI.enviar).not.toHaveBeenCalled();
    expect(TrazerAPI.leitura.mock.calls).toEqual([
      [812, 1],
      [812, 1],
      [812, 1],
    ]);
    expect(espera).toHaveBeenCalledTimes(2);
    expect(leitura.id).toBe(812);
    expect(leitura.problemas).toEqual([problema(14)]);
    expect(leitura).not.toHaveProperty('situacao');
  });

  it('a leitura retomada fica guardada: a escrita seguinte vale', async () => {
    const { fonte } = montarFonteReal();
    responde('leitura', pronta());
    await fonte.retomar(812);
    responde('deixarDeFora', {
      problema: problema(14, { estado: 'deixado' }),
      entram: 195,
    });
    const nova = await fonte.deixarDeFora(812, 14);
    expect(nova.problemas[0].estado).toBe('deixado');
  });

  it('retomada pelo id que a rota guarda (um texto): as escritas com o id da leitura valem', async () => {
    const { fonte } = montarFonteReal();
    responde('leitura', pronta());
    const leitura = await fonte.retomar('812');
    expect(leitura.id).toBe(812);
    responde('deixarDeFora', {
      problema: problema(14, { estado: 'deixado' }),
      entram: 194,
    });
    const nova = await fonte.deixarDeFora(leitura.id, 14);
    expect(nova.problemas[0].estado).toBe('deixado');
    responde('leitura', pronta({ pagina: 2, problemas: [problema(37)] }));
    const comMais = await fonte.maisProblemas(leitura.id);
    expect(TrazerAPI.leitura).toHaveBeenLastCalledWith(812, 2);
    expect(comMais.problemas.map(item => item.linha)).toEqual([14, 37]);
  });

  it('404: a leitura já foi trazida (LEITURA_NAO_ENCONTRADA), sem perguntar de novo', async () => {
    const { fonte, espera } = montarFonteReal();
    TrazerAPI.leitura.mockRejectedValue(erroHttp(404));
    await expect(fonte.retomar(812)).rejects.toMatchObject({
      name: 'LEITURA_NAO_ENCONTRADA',
    });
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(1);
    expect(espera).not.toHaveBeenCalled();
  });

  it('passou do teto de tempo: LEITURA_PENDENTE, com o id para perguntar depois', async () => {
    const { fonte, relogio } = montarFonteReal();
    TrazerAPI.leitura.mockResolvedValue({ data: LENDO });
    await expect(fonte.retomar(812)).rejects.toMatchObject({
      name: 'LEITURA_PENDENTE',
      leituraId: 812,
    });
    expect(relogio.agora).toBe(TETO);
  });

  it('a rede caiu no meio da espera: LEITURA_PENDENTE, com o id', async () => {
    const { fonte } = montarFonteReal();
    responde('leitura', LENDO);
    TrazerAPI.leitura.mockRejectedValueOnce(semRede());
    await expect(fonte.retomar(812)).rejects.toMatchObject({
      name: 'LEITURA_PENDENTE',
      leituraId: 812,
    });
  });

  it.each([
    ['vazia', 'PLANILHA_VAZIA'],
    ['sem_contato', 'PLANILHA_SEM_CONTATO'],
    ['leitura', 'LEITURA_FALHOU'],
  ])('a leitura que falhou por %s vira %s', async (erro, nome) => {
    const { fonte } = montarFonteReal();
    responde('leitura', { id: 812, situacao: 'falhou', erro });
    await expect(fonte.retomar(812)).rejects.toMatchObject({ name: nome });
  });

  it('sem acesso ganha nome', async () => {
    const { fonte } = montarFonteReal();
    TrazerAPI.leitura.mockRejectedValueOnce(erroHttp(401));
    await expect(fonte.retomar(812)).rejects.toMatchObject({
      name: 'SEM_ACESSO',
    });
  });

  it('a tela saiu: para de perguntar (LEITURA_INTERROMPIDA)', async () => {
    const { fonte, espera } = montarFonteReal();
    TrazerAPI.leitura.mockResolvedValue({ data: LENDO });
    espera.mockImplementationOnce(async () => fonte.encerrar());
    await expect(fonte.retomar(812)).rejects.toMatchObject({
      name: 'LEITURA_INTERROMPIDA',
    });
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(1);
  });
});

describe('fonte real: o envio deu certo e a espera falhou', () => {
  it('passou do teto: LEITURA_PENDENTE com o id da leitura enviada', async () => {
    const { fonte } = montarFonteReal();
    responde('enviar', LENDO);
    TrazerAPI.leitura.mockResolvedValue({ data: LENDO });
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({
      name: 'LEITURA_PENDENTE',
      leituraId: 812,
    });
  });

  it('a rede caiu: LEITURA_PENDENTE, e retomar depois não envia o arquivo de novo', async () => {
    const { fonte } = montarFonteReal();
    responde('enviar', LENDO);
    TrazerAPI.leitura.mockRejectedValueOnce(semRede());
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({
      name: 'LEITURA_PENDENTE',
      leituraId: 812,
    });
    responde('leitura', pronta());
    const leitura = await fonte.retomar(812);
    expect(leitura.id).toBe(812);
    expect(TrazerAPI.enviar).toHaveBeenCalledTimes(1);
  });

  it('o envio que falha não é leitura pendente: sobe como veio', async () => {
    const { fonte } = montarFonteReal();
    const caiu = semRede();
    TrazerAPI.enviar.mockRejectedValueOnce(caiu);
    await expect(fonte.ler(PLANILHA)).rejects.toBe(caiu);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });
});

// ---- a tela ------------------------------------------------------------------

describe('a tela retoma a leitura que o servidor já tem', () => {
  const retomando = async leitura => {
    const fonte = fonteDeMentira({
      retomar: vi.fn().mockResolvedValue(leitura),
    });
    const montada = montarTela(fonte);
    await montada.tela.retomar('l1');
    return montada;
  };

  it('mostra "lendo" enquanto pergunta e não envia arquivo nenhum', async () => {
    let terminar;
    const fonte = fonteDeMentira({
      retomar: vi.fn(
        () =>
          new Promise(resolve => {
            terminar = () => resolve(lida());
          })
      ),
    });
    const { tela } = montarTela(fonte);
    const espera = tela.retomar('l1');
    expect(tela.lendo.value).toBe(true);
    terminar();
    await espera;
    expect(tela.lendo.value).toBe(false);
    expect(fonte.ler).not.toHaveBeenCalled();
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
  });

  it('sem perguntas: cai no Conferir', async () => {
    const { tela } = await retomando(lida());
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.leitura.value.id).toBe('l1');
  });

  it('com todas as perguntas respondidas: cai no Conferir, e o Voltar leva à última pergunta', async () => {
    const { tela } = await retomando(
      lida({ perguntas: PERGUNTAS, respostas: RESPONDIDAS })
    );
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.respostas.value).toEqual(RESPONDIDAS);
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('telefone');
  });

  it('com pergunta sem resposta: cai na primeira que falta', async () => {
    const { tela } = await retomando(
      lida({ perguntas: PERGUNTAS, respostas: { clientes: 'sim_todas' } })
    );
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('telefone');
  });

  it('sem nenhuma resposta: cai na primeira pergunta', async () => {
    const { tela } = await retomando(lida({ perguntas: PERGUNTAS }));
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('clientes');
  });

  it('a leitura que o servidor não acha já foi trazida: fica no Enviar e diz isso', async () => {
    const fonte = fonteDeMentira({
      retomar: vi.fn().mockRejectedValue(erroDeNome('LEITURA_NAO_ENCONTRADA')),
    });
    const { tela } = montarTela(fonte);
    await tela.retomar('l1');
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.JA_TRAZIDA);
    expect(tela.leituraEmAberto.value).toBeNull();
  });

  it('ainda lendo depois do teto: diz que não terminou, e "tentar de novo" pergunta pela mesma leitura', async () => {
    const fonte = fonteDeMentira({
      retomar: vi
        .fn()
        .mockRejectedValueOnce(
          erroDeNome('LEITURA_PENDENTE', { leituraId: 'l1' })
        )
        .mockResolvedValueOnce(lida()),
    });
    const { tela } = montarTela(fonte);
    await tela.retomar('l1');
    expect(tela.erro.value).toBe(ERROS.DEMOROU);
    expect(tela.leituraEmAberto.value).toBe('l1');
    await tela.tentarDeNovo();
    expect(fonte.retomar.mock.calls).toEqual([['l1'], ['l1']]);
    expect(fonte.ler).not.toHaveBeenCalled();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
  });

  it('sem acesso: liga `semAcesso`', async () => {
    const fonte = fonteDeMentira({
      retomar: vi.fn().mockRejectedValue(erroDeNome('SEM_ACESSO')),
    });
    const { tela } = montarTela(fonte);
    await tela.retomar('l1');
    expect(tela.semAcesso.value).toBe(true);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
  });
});

describe('o envio que deu certo e a espera que falhou', () => {
  it('"tentar de novo" pergunta pela leitura enviada: o arquivo não vai de novo', async () => {
    const fonte = fonteDeMentira({
      ler: vi
        .fn()
        .mockRejectedValue(erroDeNome('LEITURA_PENDENTE', { leituraId: 77 })),
      retomar: vi.fn().mockResolvedValue(lida({ id: 77 })),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    expect(tela.erro.value).toBe(ERROS.DEMOROU);
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    await tela.tentarDeNovo();
    expect(fonte.ler).toHaveBeenCalledTimes(1);
    expect(fonte.retomar).toHaveBeenCalledWith(77);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.leitura.value.id).toBe(77);
  });

  it('escolher outro arquivo esquece a leitura que estava pendente', async () => {
    const fonte = fonteDeMentira({
      ler: vi
        .fn()
        .mockRejectedValueOnce(
          erroDeNome('LEITURA_PENDENTE', { leituraId: 77 })
        )
        .mockRejectedValueOnce(erroDeNome('PLANILHA_VAZIA')),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    expect(tela.leituraEmAberto.value).toBe(77);
    await tela.escolherArquivo({ name: 'b.csv' });
    expect(tela.erro.value).toBe(ERROS.VAZIA);
    expect(tela.leituraEmAberto.value).toBeNull();
  });
});

describe('a leitura que a rota guarda (`leituraEmAberto`)', () => {
  it('é o id da leitura nas perguntas e no Conferir', async () => {
    const { tela } = await noConferir();
    expect(tela.leituraEmAberto.value).toBe('l1');
    const comPerguntas = montarTela(
      fonteDeMentira({
        ler: vi.fn().mockResolvedValue(lida({ perguntas: PERGUNTAS })),
      })
    ).tela;
    expect(comPerguntas.leituraEmAberto.value).toBeNull();
    await comPerguntas.escolherArquivo({ name: 'a.csv' });
    expect(comPerguntas.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(comPerguntas.leituraEmAberto.value).toBe('l1');
  });

  it('sai ao trazer e ao recomeçar', async () => {
    const { tela } = await noConferir();
    await tela.trazer();
    expect(tela.leituraEmAberto.value).toBeNull();
    const outra = (await noConferir()).tela;
    outra.recomecar();
    expect(outra.leituraEmAberto.value).toBeNull();
  });
});
