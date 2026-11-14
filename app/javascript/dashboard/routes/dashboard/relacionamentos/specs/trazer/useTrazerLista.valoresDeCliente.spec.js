import { ETAPAS } from '../../trazer/etapas';
import { ERROS } from '../../trazer/useTrazerLista';
import {
  MARCADOR,
  erroDeNome,
  fonteDeMentira,
  lida,
  montarTela,
} from './apoioDaTela';

// #2896, E3 — a pergunta "Quais destes querem dizer cliente?" no estado da
// tela (trazer/useTrazerLista.js). Ela só existe depois que o servidor sabe
// qual coluna diz quem é cliente: por isso a resposta "Algumas" é gravada na
// hora (as outras continuam indo de uma vez, na última pergunta), e a leitura
// que volta já traz a pergunta nova, com as contagens.
const CLIENTES = { id: 'clientes' };
const TELEFONE = { id: 'telefone', coluna: 'Cel', indice: 1 };
const VALORES = {
  id: 'valores_cliente',
  coluna: 'Situação',
  indice: 6,
  preenchidas: 35,
  valores: [
    { chave: 'k-sim', valor: 'Sim', linhas: 12 },
    { chave: 'k-nao', valor: 'Não', linhas: 20 },
  ],
  outros: null,
};
const ALGUMAS = { clientes: 'algumas', colunaCliente: 6 };
const MARCADAS = { modo: 'valores', chaves: ['k-sim'] };
const FRASE_FALTA = 'RELACIONAMENTOS_TRAZER.ERROS.FALTA_VALORES_CLIENTE';

const ANTES = lida({ perguntas: [CLIENTES, TELEFONE] });
const COM_A_PERGUNTA = lida({
  perguntas: [CLIENTES, VALORES, TELEFONE],
  respostas: { ...ALGUMAS },
});
const RESPONDIDA = lida({
  perguntas: [CLIENTES, VALORES, TELEFONE],
  respostas: { ...ALGUMAS, valores_cliente: MARCADAS, telefone: 'da_pessoa' },
  resumo: { ...lida().resumo, clientes: 12 },
});

const naPrimeiraPergunta = async (leitura = ANTES, extra = {}) => {
  const fonte = fonteDeMentira({
    ler: vi.fn().mockResolvedValue(leitura),
    ...extra,
  });
  const montada = montarTela(fonte);
  await montada.tela.escolherArquivo({ name: 'a.csv' });
  return montada;
};

// A pessoa responde "Algumas", aponta a coluna e continua.
const dizerAlgumas = async tela => {
  tela.responder('clientes', 'algumas');
  tela.escolherColunaDeCliente(6);
  await tela.continuar();
};

describe('"Algumas" com a coluna: a tela grava na hora', () => {
  it('a coluna que estava em "não guardar": a planilha é lida de novo e a pessoa cai na pergunta dos valores', async () => {
    const { tela, fonte } = await naPrimeiraPergunta();
    fonte.responder.mockResolvedValue(MARCADOR);
    fonte.retomar.mockResolvedValue(COM_A_PERGUNTA);
    await dizerAlgumas(tela);
    expect(fonte.responder).toHaveBeenCalledWith('l1', ALGUMAS);
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    expect(tela.podeContinuar.value).toBe(false);
    // Não é a lista que mudou por fora: foi a pessoa que respondeu.
    expect(tela.mudou.value).toBe(false);
    expect(tela.perguntaDeNovo.value).toBe(false);
  });

  it('o servidor devolve a leitura pronta, já com a pergunta: a pessoa cai nela sem ler de novo', async () => {
    const { tela, fonte } = await naPrimeiraPergunta();
    fonte.responder.mockResolvedValue(COM_A_PERGUNTA);
    await dizerAlgumas(tela);
    expect(fonte.retomar).not.toHaveBeenCalled();
    expect(tela.perguntaAtual.value).toEqual(VALORES);
  });

  it('"Sim, todas" e "Ainda não" continuam indo só na última pergunta', async () => {
    const { tela, fonte } = await naPrimeiraPergunta();
    tela.responder('clientes', 'ainda_nao');
    await tela.continuar();
    expect(fonte.responder).not.toHaveBeenCalled();
    expect(tela.perguntaAtual.value).toEqual(TELEFONE);
  });

  it('a gravação que falha fica dita na pergunta, e a tela não sai dela', async () => {
    const { tela, fonte } = await naPrimeiraPergunta();
    fonte.responder.mockRejectedValue(new Error('caiu'));
    await dizerAlgumas(tela);
    expect(tela.perguntaAtual.value).toEqual(CLIENTES);
    expect(tela.recusaDaPergunta.value).toEqual({
      chave: 'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR',
    });
  });

  it('a releitura que não termina fica parada, com a mudança salva', async () => {
    const { tela, fonte } = await naPrimeiraPergunta();
    fonte.responder.mockResolvedValue(MARCADOR);
    fonte.retomar.mockRejectedValue(erroDeNome('LEITURA_PENDENTE'));
    await dizerAlgumas(tela);
    expect(tela.releituraParada.value).toBe(true);
    fonte.retomar.mockResolvedValue(COM_A_PERGUNTA);
    await tela.tentarDeNovo();
    expect(fonte.responder).toHaveBeenCalledTimes(1);
    expect(tela.perguntaAtual.value).toEqual(VALORES);
  });
});

describe('a pergunta dos valores, depois de respondida', () => {
  const naPerguntaDosValores = async () => {
    const montada = await naPrimeiraPergunta();
    montada.fonte.responder.mockResolvedValue(COM_A_PERGUNTA);
    await dizerAlgumas(montada.tela);
    montada.fonte.responder.mockClear();
    return montada;
  };

  it('marcar libera o Continuar; desmarcar tudo trava de novo', async () => {
    const { tela } = await naPerguntaDosValores();
    tela.responder('valores_cliente', MARCADAS);
    expect(tela.podeContinuar.value).toBe(true);
    tela.responder('valores_cliente', null);
    expect(tela.podeContinuar.value).toBe(false);
    expect(tela.respostas.value).not.toHaveProperty('valores_cliente');
  });

  it('segue para a pergunta seguinte sem gravar; a última manda tudo, com os valores', async () => {
    const { tela, fonte } = await naPerguntaDosValores();
    tela.responder('valores_cliente', MARCADAS);
    await tela.continuar();
    expect(fonte.responder).not.toHaveBeenCalled();
    expect(tela.perguntaAtual.value).toEqual(TELEFONE);
    fonte.responder.mockResolvedValue(RESPONDIDA);
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(fonte.responder).toHaveBeenCalledWith('l1', {
      ...ALGUMAS,
      valores_cliente: MARCADAS,
      telefone: 'da_pessoa',
    });
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.resumo.value.clientes).toBe(12);
  });

  it('voltar e trocar a coluna apaga os valores marcados e grava de novo na hora', async () => {
    const { tela, fonte } = await naPerguntaDosValores();
    tela.responder('valores_cliente', MARCADAS);
    tela.voltar();
    expect(tela.perguntaAtual.value).toEqual(CLIENTES);
    tela.escolherColunaDeCliente(0);
    expect(tela.respostas.value).not.toHaveProperty('valores_cliente');
    const daOutraColuna = { ...VALORES, coluna: 'Nome', indice: 0 };
    fonte.responder.mockResolvedValue(MARCADOR);
    fonte.retomar.mockResolvedValue(
      lida({
        perguntas: [CLIENTES, daOutraColuna, TELEFONE],
        respostas: { clientes: 'algumas', colunaCliente: 0 },
      })
    );
    await tela.continuar();
    expect(fonte.responder).toHaveBeenCalledWith('l1', {
      clientes: 'algumas',
      colunaCliente: 0,
    });
    expect(tela.perguntaAtual.value).toEqual(daOutraColuna);
  });

  it('voltar e dizer "Sim, todas" grava na hora e a pergunta dos valores some', async () => {
    const { tela, fonte } = await naPerguntaDosValores();
    tela.voltar();
    tela.responder('clientes', 'sim_todas');
    fonte.responder.mockResolvedValue(
      lida({
        perguntas: [CLIENTES, TELEFONE],
        respostas: { clientes: 'sim_todas' },
      })
    );
    await tela.continuar();
    expect(fonte.responder).toHaveBeenCalledWith('l1', {
      clientes: 'sim_todas',
    });
    expect(tela.perguntaAtual.value).toEqual(TELEFONE);
  });

  it('a mesma coluna de antes não grava de novo: segue para a pergunta dos valores', async () => {
    const { tela, fonte } = await naPerguntaDosValores();
    tela.voltar();
    await tela.continuar();
    expect(fonte.responder).not.toHaveBeenCalled();
    expect(tela.perguntaAtual.value).toEqual(VALORES);
  });
});

// `resposta_desconhecida` (a chave já não é um valor da coluna: a lista mudou
// por fora): a fonte dá o nome TELA_DESATUALIZADA, a tela lê a leitura de novo,
// diz que a lista mudou e a pergunta volta sem nada marcado.
describe('o servidor recusa os valores marcados', () => {
  it('lê de novo, avisa que a lista mudou e volta à pergunta, sem resposta', async () => {
    const tudoRespondido = lida({
      perguntas: [CLIENTES, VALORES],
      respostas: { ...ALGUMAS },
    });
    const { tela, fonte, avisar } = await naPrimeiraPergunta(tudoRespondido);
    await tela.continuar();
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    tela.responder('valores_cliente', MARCADAS);
    const outrosValores = {
      ...VALORES,
      valores: [{ chave: 'k-cliente', valor: 'Cliente', linhas: 9 }],
    };
    fonte.responder.mockRejectedValue(erroDeNome('TELA_DESATUALIZADA'));
    fonte.retomar.mockResolvedValue(
      lida({ perguntas: [CLIENTES, outrosValores], respostas: { ...ALGUMAS } })
    );
    await tela.continuar();
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
    expect(tela.mudou.value).toBe(true);
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual(outrosValores);
    expect(tela.respostas.value).not.toHaveProperty('valores_cliente');
    expect(tela.podeContinuar.value).toBe(false);
    expect(avisar).not.toHaveBeenCalled();
  });
});

// `falta_valores_cliente`: o servidor não traz adivinhando. A tela lê a
// leitura de novo (a pergunta e as contagens são as de agora) e leva a pessoa
// à pergunta, que diz por quê.
describe('trazer sem ter dito quem é cliente', () => {
  const noConferir = async extra => {
    const jaRespondida = lida({
      perguntas: [CLIENTES, VALORES],
      respostas: { ...ALGUMAS, valores_cliente: MARCADAS },
    });
    const montada = await naPrimeiraPergunta(jaRespondida, extra);
    await montada.tela.continuar();
    montada.fonte.responder.mockResolvedValue(jaRespondida);
    await montada.tela.continuar();
    expect(montada.tela.etapa.value).toBe(ETAPAS.CONFERIR);
    return montada;
  };

  it('vai à pergunta dos valores e diz a frase nela', async () => {
    const { tela, fonte, avisar } = await noConferir();
    fonte.trazer.mockRejectedValue(erroDeNome('FALTA_VALORES_CLIENTE'));
    fonte.retomar.mockResolvedValue(
      lida({ perguntas: [CLIENTES, VALORES], respostas: { ...ALGUMAS } })
    );
    await tela.trazer();
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    expect(tela.recusaDaPergunta.value).toEqual({ chave: FRASE_FALTA });
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.mudou.value).toBe(false);
    expect(tela.ocupado.value).toBe(false);
    expect(avisar).not.toHaveBeenCalled();
  });

  it('mesmo com outra pergunta sem resposta antes, a tela para na dos valores', async () => {
    const { tela, fonte } = await noConferir();
    fonte.trazer.mockRejectedValue(erroDeNome('FALTA_VALORES_CLIENTE'));
    fonte.retomar.mockResolvedValue(
      lida({
        perguntas: [TELEFONE, CLIENTES, VALORES],
        respostas: { ...ALGUMAS },
      })
    );
    await tela.trazer();
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    expect(tela.recusaDaPergunta.value).toEqual({ chave: FRASE_FALTA });
  });

  it('marcar alguma coisa tira a frase', async () => {
    const { tela, fonte } = await noConferir();
    fonte.trazer.mockRejectedValue(erroDeNome('FALTA_VALORES_CLIENTE'));
    fonte.retomar.mockResolvedValue(
      lida({ perguntas: [CLIENTES, VALORES], respostas: { ...ALGUMAS } })
    );
    await tela.trazer();
    tela.responder('valores_cliente', { modo: 'preenchidas' });
    expect(tela.recusaDaPergunta.value).toBeNull();
  });

  it('se a leitura de agora não tem a pergunta, fica o erro de trazer no Conferir', async () => {
    const { tela, fonte } = await noConferir();
    fonte.trazer.mockRejectedValue(erroDeNome('FALTA_VALORES_CLIENTE'));
    fonte.retomar.mockResolvedValue(
      lida({ perguntas: [CLIENTES], respostas: { clientes: 'sim_todas' } })
    );
    await tela.trazer();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.erro.value).toBe(ERROS.TRAZER);
    expect(tela.recusaDaPergunta.value).toBeNull();
  });

  it('se a leitura de novo falha por a lista já ter sido trazida, volta ao Enviar', async () => {
    const { tela, fonte } = await noConferir();
    fonte.trazer.mockRejectedValue(erroDeNome('FALTA_VALORES_CLIENTE'));
    fonte.retomar.mockRejectedValue(erroDeNome('LEITURA_NAO_ENCONTRADA'));
    await tela.trazer();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.JA_TRAZIDA);
  });
});

describe('marcar a coluna como "se é cliente" pela tela das colunas', () => {
  const SEM_PERGUNTAS = lida({
    perguntas: [CLIENTES],
    respostas: { clientes: 'ainda_nao' },
  });
  const SO_COM_OS_VALORES = lida({
    perguntas: [CLIENTES, VALORES],
    respostas: { ...ALGUMAS },
  });
  const noConferir = async () => {
    const montada = await naPrimeiraPergunta(SEM_PERGUNTAS);
    montada.fonte.responder.mockResolvedValue(SEM_PERGUNTAS);
    await montada.tela.continuar();
    expect(montada.tela.etapa.value).toBe(ETAPAS.CONFERIR);
    return montada;
  };

  // O servidor conta os valores pelas linhas que já leu: a leitura volta
  // pronta, sem ler a planilha de novo.
  it('a leitura volta pronta e a pessoa cai na pergunta dos valores, que diz por quê', async () => {
    const { tela, fonte } = await noConferir();
    fonte.trocarDestino.mockResolvedValue(SO_COM_OS_VALORES);
    await tela.trocarDestino(6, 'cliente');
    expect(fonte.retomar).not.toHaveBeenCalled();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    expect(tela.perguntaDeNovo.value).toBe(true);
  });

  it('a coluna que voltava de "não guardar": a planilha é lida de novo e a pessoa cai na mesma pergunta', async () => {
    const { tela, fonte } = await noConferir();
    fonte.trocarDestino.mockResolvedValue(MARCADOR);
    fonte.retomar.mockResolvedValue(SO_COM_OS_VALORES);
    await tela.trocarDestino(6, 'cliente');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    expect(tela.perguntaDeNovo.value).toBe(true);
  });

  it('a pessoa responde só essa pergunta e volta ao Conferir, sem passar pelas que já respondeu', async () => {
    const tudoRespondido = lida({
      perguntas: [CLIENTES, TELEFONE],
      respostas: { clientes: 'ainda_nao', telefone: 'da_pessoa' },
    });
    const { tela, fonte } = await naPrimeiraPergunta(tudoRespondido);
    await tela.continuar();
    fonte.responder.mockResolvedValue(tudoRespondido);
    await tela.continuar();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    fonte.trocarDestino.mockResolvedValue(
      lida({
        perguntas: [CLIENTES, VALORES, TELEFONE],
        respostas: { ...ALGUMAS, telefone: 'da_pessoa' },
      })
    );
    await tela.trocarDestino(6, 'cliente');
    expect(tela.perguntaAtual.value).toEqual(VALORES);
    fonte.responder.mockClear();
    fonte.responder.mockResolvedValue(
      lida({
        perguntas: [CLIENTES, VALORES, TELEFONE],
        respostas: {
          ...ALGUMAS,
          valores_cliente: MARCADAS,
          telefone: 'da_pessoa',
        },
      })
    );
    tela.responder('valores_cliente', MARCADAS);
    await tela.continuar();
    expect(fonte.responder).toHaveBeenCalledWith('l1', {
      ...ALGUMAS,
      valores_cliente: MARCADAS,
      telefone: 'da_pessoa',
    });
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.perguntaDeNovo.value).toBe(false);
  });
});
