import { effectScope } from 'vue';
import { leituraDaTela } from '../../fonte/trazerTraducao';
import { ETAPAS } from '../../trazer/etapas';
import { useTrazerLista } from '../../trazer/useTrazerLista';
const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
  estado: 'aberto',
};

const EMAIL = {
  linha: 5,
  tipo: 'email',
  nome: 'Davi Dornelino',
  valor: 'davi.exemplo.com.br',
  estado: 'aberto',
};

const SEM_NOME = {
  linha: 6,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11987650005',
  estado: 'aberto',
};

const SEM_CONTATO = {
  linha: 7,
  tipo: 'sem_contato',
  nome: 'Elisa Esteveira',
  valor: '',
  estado: 'aberto',
};

const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  tem_empresa: true,
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'telefone', duvidosa: true },
    { indice: 5, nome: 'Situação', destino: 'cliente' },
    { indice: 6, nome: 'Fone 2', destino: 'informacao' },
  ],
  perguntas: [
    { id: 'clientes' },
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: {
    clientes: 'algumas',
    coluna_cliente: 5,
    telefone: 'da_pessoa',
  },
  resumo: { total: 7, novas: 2, completadas: 0, comProblema: 4, juntadas: 0 },
  exemplos: [],
  problemas: [TELEFONE, EMAIL, SEM_NOME, SEM_CONTATO],
  problemas_total: 4,
  pagina: 1,
  por_pagina: 200,
};

// Depois de a pessoa mandar o telefone para outra coluna: a pergunta do
// telefone sai e a resposta dela deixa de valer.
const SEM_A_PERGUNTA_DO_TELEFONE = {
  ...PRONTA,
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'informacao' },
    { indice: 5, nome: 'Situação', destino: 'cliente' },
    { indice: 6, nome: 'Fone 2', destino: 'telefone' },
  ],
  perguntas: [{ id: 'clientes' }],
  respostas: { clientes: 'algumas', coluna_cliente: 5 },
};

describe('useTrazerLista: a pergunta e a resposta que somem depois da troca de coluna', () => {
  const LIDA = leituraDaTela(PRONTA);
  const DEPOIS = leituraDaTela(SEM_A_PERGUNTA_DO_TELEFONE);
  const montar = async (daFonte = {}) => {
    const avisar = vi.fn();
    const fonte = {
      ler: vi.fn(async () => LIDA),
      responder: vi.fn(async () => LIDA),
      ...daFonte,
    };
    const tela = effectScope().run(() => useTrazerLista({ fonte, avisar }));
    await tela.escolherArquivo({ name: 'a.csv' });
    await tela.continuar();
    await tela.continuar();
    return { tela, avisar, fonte };
  };

  it('chega ao conferir com as respostas que o servidor guardou', async () => {
    const { tela } = await montar();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.respostas.value).toEqual({
      clientes: 'algumas',
      colunaCliente: 5,
      telefone: 'da_pessoa',
    });
  });

  it('a pergunta do telefone saiu e o resto continua respondido: fica no conferir, sem a resposta velha, e o Voltar cai numa pergunta que existe', async () => {
    const { tela } = await montar({ trocarDestino: vi.fn(async () => DEPOIS) });
    expect(await tela.trocarDestino(6, 'telefone')).toBe(true);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.respostas.value).toEqual({
      clientes: 'algumas',
      colunaCliente: 5,
    });
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual({ id: 'clientes' });
    expect(tela.podeContinuar.value).toBe(true);
  });

  it('continuar depois disso manda só o que ainda vale e volta ao conferir', async () => {
    const responder = vi.fn(async () => DEPOIS);
    const { tela } = await montar({
      responder,
      trocarDestino: vi.fn(async () => DEPOIS),
    });
    await tela.trocarDestino(6, 'telefone');
    tela.voltar();
    responder.mockClear();
    await tela.continuar();
    expect(responder).toHaveBeenCalledWith(812, {
      clientes: 'algumas',
      colunaCliente: 5,
    });
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('a resposta de clientes sumiu: a tela mostra a pergunta de novo, sem resposta, e segue quando a pessoa responde', async () => {
    const semResposta = { ...DEPOIS, respostas: {} };
    const respondida = { ...DEPOIS, respostas: { clientes: 'ainda_nao' } };
    const responder = vi.fn(async () => respondida);
    const { tela } = await montar({
      responder,
      trocarDestino: vi.fn(async () => semResposta),
    });
    responder.mockClear();
    expect(await tela.trocarDestino(5, 'informacao')).toBe(true);
    expect(tela.respostas.value).toEqual({});
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual({ id: 'clientes' });
    expect(tela.podeContinuar.value).toBe(false);
    tela.responder('clientes', 'ainda_nao');
    await tela.continuar();
    expect(responder).toHaveBeenCalledWith(812, { clientes: 'ainda_nao' });
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('"algumas" ficou sem a coluna: a pergunta de clientes é feita de novo', async () => {
    const semAColuna = { ...DEPOIS, respostas: { clientes: 'algumas' } };
    const { tela } = await montar({
      trocarDestino: vi.fn(async () => semAColuna),
    });
    await tela.trocarDestino(5, 'cidade');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value).toEqual({ id: 'clientes' });
    expect(tela.podeContinuar.value).toBe(false);
  });

  it('a pergunta do telefone continua, mas sem resposta: é ela que aparece de novo', async () => {
    const semOTelefone = {
      ...LIDA,
      respostas: { clientes: 'algumas', colunaCliente: 5 },
    };
    const { tela } = await montar({
      trocarDestino: vi.fn(async () => semOTelefone),
    });
    await tela.trocarDestino(6, 'cidade');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('telefone');
    expect(tela.podeContinuar.value).toBe(false);
  });

  it('a troca que o servidor recusa não leva a pergunta nenhuma', async () => {
    const { tela } = await montar({
      trocarDestino: vi.fn().mockRejectedValue(new Error('caiu')),
    });
    expect(await tela.trocarDestino(6, 'cidade')).toBe(false);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('a escrita que não mexe nas perguntas deixa as respostas como estavam', async () => {
    const { tela } = await montar({
      deixarDeFora: vi.fn(async () => LIDA),
    });
    await tela.deixarDeFora(4);
    expect(tela.respostas.value).toEqual(LIDA.respostas);
    expect(tela.estado.value.totalDePerguntas).toBe(2);
  });

  it('a fonte que não devolve perguntas nem respostas não apaga o que a tela tem', async () => {
    const { perguntas, respostas, ...semElas } = LIDA;
    const { tela } = await montar({
      deixarDeFora: vi.fn(async () => semElas),
    });
    await tela.deixarDeFora(4);
    expect(tela.respostas.value).toEqual(respostas);
    expect(tela.estado.value.totalDePerguntas).toBe(perguntas.length);
  });
});
