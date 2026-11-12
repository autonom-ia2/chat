import { effectScope } from 'vue';
import {
  PLANILHAS_DE_DEMO,
  esquecerMemoriaDaDemo,
  trazerFonte,
} from '../../fonte/trazerFonte';
import { ETAPAS } from '../../trazer/etapas';
import { ERROS, useTrazerLista } from '../../trazer/useTrazerLista';

// #2896, Fatia 2 (item 18 da revisão do dono) — a demonstração faz o papel do
// servidor nas colunas e nas perguntas: trocar o destino de uma coluna
// (app/services/relacionamentos/trazer/trocar_destino.rb), responder
// (responder.rb) e o que as perguntas e as respostas viram depois
// (perguntas.rb). Como no servidor, cada alvo (nome, telefone, e-mail, empresa)
// é de uma coluna só, e a troca que mexe num alvo faz a planilha ser lida de
// novo: a fonte devolve o marcador `lendo` e a leitura nova vem do `retomar`.
const COLUNA = {
  NOME: 0,
  CEL: 1,
  EMAIL: 2,
  EMPRESA: 3,
  CIDADE: 4,
  SITUACAO: 5,
  ANIVERSARIO: 6,
};
const SEM_PARA_QUE = '';

const fonteDemo = (planilha = null) =>
  trazerFonte({
    demo: 'cheio',
    planilha,
    carregarDemo: () => import('../../demo/trazer.js'),
    atraso: 0,
    atrasoDaLeitura: 0,
  });
const lida = async (planilha = null) => {
  const fonte = fonteDemo(planilha);
  const leitura = await fonte.ler(null);
  return { fonte, id: leitura.id, leitura };
};
const daColuna = (leitura, indice) =>
  leitura.colunas.find(coluna => coluna.indice === indice);
const destinos = leitura => leitura.colunas.map(coluna => coluna.destino);
const marcador = id => ({ situacao: 'lendo', id });
// A escrita que faz ler de novo: confere o marcador e devolve a leitura nova.
const relendo = async (fonte, id, escrita) => {
  expect(await escrita).toEqual(marcador(id));
  return fonte.retomar(id);
};

beforeEach(() => esquecerMemoriaDaDemo());

describe('as colunas da planilha de exemplo', () => {
  it('cada alvo é de uma coluna só, e o resto é informação com o campo', async () => {
    const { leitura } = await lida();
    expect(leitura.colunas).toEqual([
      { indice: COLUNA.NOME, nome: 'Nome', destino: 'nome' },
      { indice: COLUNA.CEL, nome: 'Cel', destino: 'telefone', duvidosa: true },
      { indice: COLUNA.EMAIL, nome: 'E-mail', destino: 'email' },
      { indice: COLUNA.EMPRESA, nome: 'Empresa', destino: 'empresa' },
      ...['Cidade', 'Situação', 'Aniversário'].map((nome, posicao) => ({
        indice: COLUNA.CIDADE + posicao,
        nome,
        destino: 'informacao',
        campo: { nome, para_que_serve: SEM_PARA_QUE },
      })),
    ]);
    expect(leitura.temEmpresa).toBe(true);
    expect(leitura.perguntas).toEqual([
      { id: 'clientes' },
      { id: 'telefone', coluna: 'Cel', indice: COLUNA.CEL },
    ]);
    expect(leitura.respostas).toEqual({});
  });
});

describe('trocar o destino de uma coluna', () => {
  it('a informação que vira cidade vale na hora e perde o campo', async () => {
    const { fonte, id } = await lida();
    const nova = await fonte.trocarDestino(id, COLUNA.CIDADE, 'cidade');
    expect(daColuna(nova, COLUNA.CIDADE)).toEqual({
      indice: COLUNA.CIDADE,
      nome: 'Cidade',
      destino: 'cidade',
    });
    expect(daColuna(nova, COLUNA.CEL).destino).toBe('telefone');
  });

  it('a informação guarda o nome do campo e o "para que serve"; sem eles, fica o título', async () => {
    const { fonte, id } = await lida();
    const campo = {
      nome: ' Nascimento ',
      para_que_serve: 'dia do aniversário',
    };
    const nova = await fonte.trocarDestino(
      id,
      COLUNA.ANIVERSARIO,
      'informacao',
      campo
    );
    expect(daColuna(nova, COLUNA.ANIVERSARIO).campo).toEqual({
      nome: 'Nascimento',
      para_que_serve: 'dia do aniversário',
    });
    // Foi para outro destino e voltou: o que a pessoa tinha escrito some.
    await fonte.trocarDestino(id, COLUNA.ANIVERSARIO, 'cidade');
    const voltou = await fonte.trocarDestino(
      id,
      COLUNA.ANIVERSARIO,
      'informacao'
    );
    expect(daColuna(voltou, COLUNA.ANIVERSARIO).campo).toEqual({
      nome: 'Aniversário',
      para_que_serve: SEM_PARA_QUE,
    });
  });

  it('recusa o nome do campo longo demais, como o servidor', async () => {
    const { fonte, id, leitura } = await lida();
    await expect(
      fonte.trocarDestino(id, COLUNA.ANIVERSARIO, 'informacao', {
        nome: 'a'.repeat(256),
        para_que_serve: '',
      })
    ).rejects.toMatchObject({ name: 'VALOR_INVALIDO', motivo: 'muito_longo' });
    expect(await fonte.retomar(id)).toEqual(leitura);
  });

  it('a coluna que a leitura não tem dá o mesmo erro da fonte real', async () => {
    const { fonte, id } = await lida();
    await expect(fonte.trocarDestino(id, 99, 'cidade')).rejects.toMatchObject({
      name: 'COLUNA_NAO_ENCONTRADA',
    });
    // O nome da coluna não vale: quem identifica a coluna é o índice.
    await expect(
      fonte.trocarDestino(id, 'Cidade', 'cidade')
    ).rejects.toMatchObject({ name: 'COLUNA_NAO_ENCONTRADA' });
  });

  it('o destino que não existe é tela desatualizada', async () => {
    const { fonte, id } = await lida();
    await expect(
      fonte.trocarDestino(id, COLUNA.CIDADE, 'endereco')
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
  });

  it('a coluna que vira telefone faz ler de novo e toma o lugar da que era', async () => {
    const { fonte, id } = await lida();
    const nova = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.CIDADE, 'telefone')
    );
    expect(daColuna(nova, COLUNA.CIDADE)).toEqual({
      indice: COLUNA.CIDADE,
      nome: 'Cidade',
      destino: 'telefone',
    });
    // A que era o telefone volta a ser informação, com o título dela.
    expect(daColuna(nova, COLUNA.CEL)).toEqual({
      indice: COLUNA.CEL,
      nome: 'Cel',
      destino: 'informacao',
      campo: { nome: 'Cel', para_que_serve: SEM_PARA_QUE },
    });
    // Coluna escolhida pela pessoa não é duvidosa.
    expect(nova.colunas.some(coluna => 'duvidosa' in coluna)).toBe(false);
    expect(destinos(nova).filter(d => d === 'telefone')).toHaveLength(1);
  });

  it('"não guardar" vale na hora; voltar de "não guardar" faz ler de novo', async () => {
    const { fonte, id } = await lida();
    const fora = await fonte.trocarDestino(id, COLUNA.SITUACAO, 'nao_guardar');
    expect(daColuna(fora, COLUNA.SITUACAO)).toEqual({
      indice: COLUNA.SITUACAO,
      nome: 'Situação',
      destino: 'nao_guardar',
    });
    const voltou = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.SITUACAO, 'informacao')
    );
    expect(daColuna(voltou, COLUNA.SITUACAO).destino).toBe('informacao');
  });

  it('recusa tirar a última coluna de telefone ou e-mail', async () => {
    const { fonte, id } = await lida();
    const semEmail = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMAIL, 'nao_guardar')
    );
    await expect(
      fonte.trocarDestino(id, COLUNA.CEL, 'cidade')
    ).rejects.toMatchObject({ name: 'TROCA_SEM_CONTATO' });
    expect(await fonte.retomar(id)).toEqual(semEmail);
  });

  it('o telefone da empresa só existe com coluna de empresa', async () => {
    const { fonte, id } = await lida();
    const comTelefone = await fonte.trocarDestino(
      id,
      COLUNA.CIDADE,
      'telefone_da_empresa'
    );
    expect(daColuna(comTelefone, COLUNA.CIDADE).destino).toBe(
      'telefone_da_empresa'
    );
    // A própria coluna de empresa não pode virar o telefone da empresa.
    await expect(
      fonte.trocarDestino(id, COLUNA.EMPRESA, 'telefone_da_empresa')
    ).rejects.toMatchObject({ name: 'SEM_EMPRESA' });

    const semEmpresa = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMPRESA, 'nao_guardar')
    );
    expect(semEmpresa.temEmpresa).toBe(false);
    // O telefone da empresa ficou sem empresa: volta a ser informação.
    expect(daColuna(semEmpresa, COLUNA.CIDADE)).toMatchObject({
      destino: 'informacao',
      campo: { nome: 'Cidade', para_que_serve: SEM_PARA_QUE },
    });
    await expect(
      fonte.trocarDestino(id, COLUNA.CIDADE, 'telefone_da_empresa')
    ).rejects.toMatchObject({ name: 'SEM_EMPRESA' });
  });
});

describe('responder às perguntas', () => {
  it('"é da pessoa": a coluna deixa de ser duvidosa, sem ler de novo, e a pergunta continua respondida', async () => {
    const { fonte, id, leitura } = await lida();
    const nova = await fonte.responder(id, {
      clientes: 'ainda_nao',
      telefone: 'da_pessoa',
    });
    expect(daColuna(nova, COLUNA.CEL)).toEqual({
      indice: COLUNA.CEL,
      nome: 'Cel',
      destino: 'telefone',
    });
    expect(nova.perguntas).toEqual(leitura.perguntas);
    expect(nova.respostas).toEqual({
      clientes: 'ainda_nao',
      telefone: 'da_pessoa',
    });
    expect(nova.exemplos.some(exemplo => exemplo.cliente)).toBe(false);
  });

  it('"é da empresa" faz ler de novo: a coluna vira telefone da empresa', async () => {
    const { fonte, id, leitura } = await lida();
    const nova = await relendo(
      fonte,
      id,
      fonte.responder(id, { clientes: 'sim_todas', telefone: 'da_empresa' })
    );
    expect(daColuna(nova, COLUNA.CEL)).toEqual({
      indice: COLUNA.CEL,
      nome: 'Cel',
      destino: 'telefone_da_empresa',
    });
    expect(nova.perguntas).toEqual(leitura.perguntas);
    expect(nova.respostas).toEqual({
      clientes: 'sim_todas',
      telefone: 'da_empresa',
    });
    expect(nova.exemplos.every(exemplo => exemplo.cliente)).toBe(true);
  });

  it('"não usar" faz ler de novo: a coluna deixa de ser guardada', async () => {
    const { fonte, id } = await lida();
    const nova = await relendo(
      fonte,
      id,
      fonte.responder(id, { clientes: 'ainda_nao', telefone: 'nao_usar' })
    );
    expect(daColuna(nova, COLUNA.CEL).destino).toBe('nao_guardar');
    expect(nova.respostas.telefone).toBe('nao_usar');
  });

  it('as mesmas respostas de novo não fazem ler outra vez', async () => {
    const { fonte, id } = await lida();
    const respostas = { clientes: 'sim_todas', telefone: 'da_empresa' };
    const primeira = await relendo(fonte, id, fonte.responder(id, respostas));
    expect(await fonte.responder(id, respostas)).toEqual(primeira);
  });

  it('"algumas": a coluna escolhida diz quem é cliente; outra resposta devolve a coluna para informação', async () => {
    const { fonte, id } = await lida();
    const algumas = await fonte.responder(id, {
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      telefone: 'da_pessoa',
    });
    expect(daColuna(algumas, COLUNA.SITUACAO)).toEqual({
      indice: COLUNA.SITUACAO,
      nome: 'Situação',
      destino: 'cliente',
    });
    expect(algumas.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      telefone: 'da_pessoa',
    });
    expect(algumas.exemplos.map(e => e.cliente)).toEqual([true, false, true]);

    const todas = await fonte.responder(id, {
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    expect(daColuna(todas, COLUNA.SITUACAO)).toEqual({
      indice: COLUNA.SITUACAO,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: SEM_PARA_QUE },
    });
    expect(todas.respostas).toEqual({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    expect(todas.exemplos.every(exemplo => exemplo.cliente)).toBe(true);
  });

  it.each([
    ['a coluna que acha a pessoa não diz quem é cliente', COLUNA.NOME],
    ['a coluna que não existe', 99],
  ])('%s: tela desatualizada, sem guardar nada', async (_nome, coluna) => {
    const { fonte, id, leitura } = await lida();
    await expect(
      fonte.responder(id, {
        clientes: 'algumas',
        colunaCliente: coluna,
        telefone: 'da_pessoa',
      })
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
    expect(await fonte.retomar(id)).toEqual(leitura);
  });

  it('a resposta que não existe é tela desatualizada', async () => {
    const { fonte, id } = await lida();
    await expect(
      fonte.responder(id, { clientes: 'talvez', telefone: 'da_pessoa' })
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
    await expect(
      fonte.responder(id, { clientes: 'sim_todas', telefone: 'do_vizinho' })
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
  });

  it('"é da empresa" sem coluna de empresa é recusado, e nada do pedido fica', async () => {
    const { fonte, id } = await lida();
    await fonte.responder(id, { clientes: 'ainda_nao', telefone: 'da_pessoa' });
    const semEmpresa = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMPRESA, 'nao_guardar')
    );
    await expect(
      fonte.responder(id, { clientes: 'sim_todas', telefone: 'da_empresa' })
    ).rejects.toMatchObject({ name: 'SEM_EMPRESA' });
    expect(await fonte.retomar(id)).toEqual(semEmpresa);
  });

  it('"não usar" no telefone que é a única coluna de contato é recusado', async () => {
    const { fonte, id } = await lida();
    await fonte.responder(id, { clientes: 'sim_todas', telefone: 'da_pessoa' });
    await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMAIL, 'nao_guardar')
    );
    await expect(
      fonte.responder(id, { clientes: 'sim_todas', telefone: 'nao_usar' })
    ).rejects.toMatchObject({ name: 'TROCA_SEM_CONTATO' });
  });
});

describe('as perguntas e as respostas acompanham as colunas', () => {
  const respondida = async respostas => {
    const montada = await lida();
    const voltou = await montada.fonte.responder(montada.id, respostas);
    const leitura =
      voltou.situacao === 'lendo'
        ? await montada.fonte.retomar(montada.id)
        : voltou;
    return { ...montada, leitura };
  };
  const SO_CLIENTES = [{ id: 'clientes' }];

  it('a coluna do telefone duvidoso vai para outro lugar: a pergunta e a resposta dela somem', async () => {
    const { fonte, id } = await respondida({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    const nova = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.CEL, 'cidade')
    );
    expect(nova.perguntas).toEqual(SO_CLIENTES);
    expect(nova.respostas).toEqual({ clientes: 'sim_todas' });
  });

  it('o telefone passa para outra coluna: a resposta antiga deixa de valer', async () => {
    const { fonte, id } = await respondida({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    const nova = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.CIDADE, 'telefone')
    );
    expect(nova.perguntas).toEqual(SO_CLIENTES);
    expect(nova.respostas).toEqual({ clientes: 'sim_todas' });
  });

  it('a coluna que era o telefone da empresa pela resposta muda na hora, e a resposta some', async () => {
    const { fonte, id } = await respondida({
      clientes: 'sim_todas',
      telefone: 'da_empresa',
    });
    const nova = await fonte.trocarDestino(id, COLUNA.CEL, 'cidade');
    expect(nova.perguntas).toEqual(SO_CLIENTES);
    expect(nova.respostas).toEqual({ clientes: 'sim_todas' });
  });

  // A coluna escolhida pela pessoa não é duvidosa: sem dúvida e sem resposta,
  // o servidor não tem o que perguntar.
  it('sem resposta ainda, a troca que faz ler de novo tira a dúvida e a pergunta do telefone', async () => {
    const { fonte, id } = await lida();
    const nova = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMPRESA, 'nao_guardar')
    );
    expect(daColuna(nova, COLUNA.CEL)).toEqual({
      indice: COLUNA.CEL,
      nome: 'Cel',
      destino: 'telefone',
    });
    expect(nova.perguntas).toEqual(SO_CLIENTES);
  });

  it('a troca de outra coluna não mexe na pergunta nem na resposta do telefone', async () => {
    const { fonte, id, leitura } = await respondida({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    const nova = await fonte.trocarDestino(id, COLUNA.CIDADE, 'cidade');
    expect(nova.perguntas).toEqual(leitura.perguntas);
    expect(nova.respostas).toEqual(leitura.respostas);
  });

  it('responder ao telefone depois que a pergunta sumiu é tela desatualizada', async () => {
    const { fonte, id } = await respondida({
      clientes: 'sim_todas',
      telefone: 'da_empresa',
    });
    await fonte.trocarDestino(id, COLUNA.CEL, 'cidade');
    await expect(
      fonte.responder(id, { clientes: 'sim_todas', telefone: 'da_pessoa' })
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
  });

  it('a coluna "cliente" que muda tira a resposta de clientes: a pergunta volta sem resposta', async () => {
    const { fonte, id } = await respondida({
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      telefone: 'da_pessoa',
    });
    const nova = await fonte.trocarDestino(id, COLUNA.SITUACAO, 'cidade');
    expect(nova.respostas).toEqual({ telefone: 'da_pessoa' });
    expect(nova.exemplos.some(exemplo => exemplo.cliente)).toBe(false);
  });

  it('a coluna marcada "cliente" pela tela das colunas vale como "algumas", menos com "sim, todas"', async () => {
    const aindaNao = await respondida({
      clientes: 'ainda_nao',
      telefone: 'da_pessoa',
    });
    const marcada = await aindaNao.fonte.trocarDestino(
      aindaNao.id,
      COLUNA.SITUACAO,
      'cliente'
    );
    expect(marcada.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      telefone: 'da_pessoa',
    });
    expect(marcada.exemplos.map(e => e.cliente)).toEqual([true, false, true]);

    esquecerMemoriaDaDemo();
    const todas = await respondida({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    const comColuna = await todas.fonte.trocarDestino(
      todas.id,
      COLUNA.SITUACAO,
      'cliente'
    );
    expect(comColuna.respostas).toEqual({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
  });
});

describe('?planilha=mudanca_desfeita: a troca que faz ler de novo é desfeita', () => {
  it('a leitura volta como estava, com os consertos e com o aviso', async () => {
    const { fonte, id } = await lida('mudanca_desfeita');
    const antes = await fonte.consertar(id, 14, '(11) 97380-0014');
    expect(antes).not.toHaveProperty('aviso');
    const voltou = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMAIL, 'nao_guardar')
    );
    expect(voltou).toEqual({ ...antes, aviso: 'mudanca_desfeita' });
  });

  it.each([
    [
      'trocar uma coluna na hora',
      (fonte, id) => fonte.trocarDestino(id, COLUNA.CIDADE, 'cidade'),
    ],
    [
      'consertar uma linha',
      (fonte, id) => fonte.consertar(id, 14, '(11) 97380-0014'),
    ],
    ['deixar uma linha de fora', (fonte, id) => fonte.deixarDeFora(id, 14)],
    ['voltar atrás numa linha', (fonte, id) => fonte.reabrir(id, 14)],
    [
      'responder às perguntas',
      (fonte, id) =>
        fonte.responder(id, { clientes: 'sim_todas', telefone: 'da_pessoa' }),
    ],
  ])(
    'o aviso some na escrita seguinte que dá certo: %s',
    async (_nome, escrita) => {
      const { fonte, id } = await lida('mudanca_desfeita');
      await fonte.trocarDestino(id, COLUNA.EMAIL, 'nao_guardar');
      expect((await fonte.retomar(id)).aviso).toBe('mudanca_desfeita');
      expect(await escrita(fonte, id)).not.toHaveProperty('aviso');
      expect(await fonte.retomar(id)).not.toHaveProperty('aviso');
    }
  );

  it('a escrita recusada não tira o aviso', async () => {
    const { fonte, id } = await lida('mudanca_desfeita');
    await fonte.trocarDestino(id, COLUNA.EMAIL, 'nao_guardar');
    await expect(fonte.consertar(id, 14, '')).rejects.toMatchObject({
      name: 'VALOR_INVALIDO',
    });
    expect((await fonte.retomar(id)).aviso).toBe('mudanca_desfeita');
  });

  it('na planilha de exemplo comum a troca vale e nenhum aviso vem', async () => {
    const { fonte, id } = await lida();
    const nova = await relendo(
      fonte,
      id,
      fonte.trocarDestino(id, COLUNA.EMAIL, 'nao_guardar')
    );
    expect(nova).not.toHaveProperty('aviso');
    expect(daColuna(nova, COLUNA.EMAIL).destino).toBe('nao_guardar');
  });
});

describe('os dois estados novos, na tela', () => {
  const montarTela = planilha => {
    const escopo = effectScope();
    const tela = escopo.run(() =>
      useTrazerLista({ fonte: fonteDemo(planilha), avisar: vi.fn() })
    );
    return { tela, parar: () => escopo.stop() };
  };
  const ateOConferir = async tela => {
    await tela.usarExemplo();
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  };

  it('os dois valores de ?planilha= existem', () => {
    expect(PLANILHAS_DE_DEMO).toEqual(
      expect.arrayContaining(['mudanca_desfeita', 'vencida'])
    );
    expect(fonteDemo('mudanca_desfeita').planilhaDeDemo).toBe(
      'mudanca_desfeita'
    );
    expect(fonteDemo('vencida').planilhaDeDemo).toBe('vencida');
  });

  it('mudanca_desfeita: a troca de uma coluna deixa o Conferir com o aviso', async () => {
    const { tela, parar } = montarTela('mudanca_desfeita');
    await ateOConferir(tela);
    expect(tela.leitura.value.aviso).toBeUndefined();
    await tela.trocarDestino(COLUNA.EMAIL, 'nao_guardar');
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.leitura.value.aviso).toBe('mudanca_desfeita');
    expect(daColuna(tela.leitura.value, COLUNA.EMAIL).destino).toBe('email');
    parar();
  });

  it('vencida: a leitura volta CONFERENCIA_VENCIDA e a tela fica no Enviar com a frase', async () => {
    await expect(fonteDemo('vencida').ler(null)).rejects.toMatchObject({
      name: 'CONFERENCIA_VENCIDA',
    });
    const { tela, parar } = montarTela('vencida');
    await tela.usarExemplo();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.VENCIDA);
    parar();
  });

  it('a resposta que faz ler de novo leva a pessoa ao Conferir, com a coluna trocada', async () => {
    const { tela, parar } = montarTela();
    await tela.usarExemplo();
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'da_empresa');
    await tela.continuar();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.relendo.value).toBe(false);
    expect(daColuna(tela.leitura.value, COLUNA.CEL).destino).toBe(
      'telefone_da_empresa'
    );
    parar();
  });
});
