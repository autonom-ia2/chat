import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';

// #2896, E3 — a demonstração faz o papel do servidor na pergunta "Quais destes
// querem dizer cliente?": a planilha de exemplo tem a coluna "Já é cliente?",
// com valores variados; marcar uma coluna como "cliente" já devolve a leitura
// pronta com a pergunta e a contagem de cada valor (o servidor conta pelas
// linhas que já leu; só lê a planilha de novo quando a coluna volta de "não
// guardar"); só uma coluna diz quem é cliente; a resposta vale só para aquela
// coluna; e o trazer não adivinha.
const COLUNA = { EMPRESA: 3, CIDADE: 4, SITUACAO: 5, ANIVERSARIO: 6, JA_E: 7 };

const fonteDemo = () =>
  trazerFonte({
    demo: 'cheio',
    carregarDemo: () => import('../../demo/trazer.js'),
    atraso: 0,
    atrasoDaLeitura: 0,
  });
const lida = async () => {
  const fonte = fonteDemo();
  const leitura = await fonte.ler(null);
  return { fonte, id: leitura.id, leitura };
};
const ids = leitura => leitura.perguntas.map(pergunta => pergunta.id);
const dosValores = leitura =>
  leitura.perguntas.find(pergunta => pergunta.id === 'valores_cliente');
const chaveDe = (leitura, valor) =>
  dosValores(leitura).valores.find(item => item.valor === valor).chave;
const marcador = id => ({ situacao: 'lendo', id });
// O código do servidor que a recusa carrega (o nome dela é o que a tela usa).
const codigoDa = falha => falha.cause.response.data.error;

// "Algumas" com a coluna: a leitura já volta pronta, com a pergunta.
const comAColuna = async (coluna = COLUNA.JA_E) => {
  const { fonte, id } = await lida();
  const leitura = await fonte.responder(id, {
    clientes: 'algumas',
    colunaCliente: coluna,
  });
  return { fonte, id, leitura };
};
const ALGUMAS = { clientes: 'algumas', colunaCliente: COLUNA.JA_E };

beforeEach(() => esquecerMemoriaDaDemo());

describe('demonstração: a planilha de exemplo', () => {
  it('tem a coluna "Já é cliente?", que chega como informação', async () => {
    const { leitura } = await lida();
    expect(leitura.colunas.find(c => c.indice === COLUNA.JA_E)).toEqual({
      indice: COLUNA.JA_E,
      nome: 'Já é cliente?',
      destino: 'informacao',
      campo: { nome: 'Já é cliente?', para_que_serve: '' },
    });
  });

  it('antes de a pessoa dizer a coluna, não há pergunta dos valores nem cliente no resumo', async () => {
    const { leitura } = await lida();
    expect(ids(leitura)).toEqual(['clientes', 'telefone']);
    expect(leitura.resumo.clientes).toBe(0);
  });
});

describe('demonstração: a pergunta dos valores', () => {
  it('aparece depois de "Algumas" com a coluna, com a contagem de cada valor', async () => {
    const { leitura } = await comAColuna();
    expect(ids(leitura)).toEqual(['clientes', 'valores_cliente', 'telefone']);
    const pergunta = dosValores(leitura);
    expect(pergunta).toMatchObject({
      id: 'valores_cliente',
      coluna: 'Já é cliente?',
      indice: COLUNA.JA_E,
      outros: null,
    });
    expect(
      pergunta.valores.map(({ valor, linhas }) => [valor, linhas])
    ).toEqual([
      ['Sim', 96],
      ['Não', 61],
      ['Sim, desde 2019', 14],
      ['Cliente antigo', 9],
      ['Ainda não', 7],
      ['Em negociação', 5],
    ]);
    expect(pergunta.preenchidas).toBe(192);
    const chaves = pergunta.valores.map(item => item.chave);
    expect(chaves.every(chave => typeof chave === 'string' && chave)).toBe(
      true
    );
    expect(new Set(chaves).size).toBe(chaves.length);
  });

  it('nasce sem resposta: ninguém é cliente até a pessoa marcar', async () => {
    const { leitura } = await comAColuna();
    expect(leitura.respostas).toEqual(ALGUMAS);
    expect(leitura.exemplos.map(e => e.cliente)).toEqual([false, false, false]);
    expect(leitura.resumo.clientes).toBe(0);
  });

  it('a coluna com mais de 20 valores mostra 20 e conta o resto em `outros`', async () => {
    const { leitura } = await comAColuna(COLUNA.ANIVERSARIO);
    const pergunta = dosValores(leitura);
    expect(pergunta.valores).toHaveLength(20);
    expect(pergunta.outros).toEqual({ valores: 7, linhas: 12 });
    const linhas = pergunta.valores.map(item => item.linhas);
    expect(linhas).toEqual([...linhas].sort((a, b) => b - a));
    expect(pergunta.preenchidas).toBe(
      linhas.reduce((soma, n) => soma + n, 0) + pergunta.outros.linhas
    );
  });

  it('"Sim, todas" e "Ainda não" não mostram a pergunta', async () => {
    const { fonte, id } = await comAColuna();
    const todas = await fonte.responder(id, { clientes: 'sim_todas' });
    expect(ids(todas)).toEqual(['clientes', 'telefone']);
    expect(todas.resumo.clientes).toBe(todas.resumo.entram);
    const aindaNao = await fonte.responder(id, { clientes: 'ainda_nao' });
    expect(ids(aindaNao)).toEqual(['clientes', 'telefone']);
    expect(aindaNao.resumo.clientes).toBe(0);
  });

  it('marcar a coluna pela tela das colunas devolve a leitura pronta, já com a pergunta', async () => {
    const { fonte, id } = await lida();
    const leitura = await fonte.trocarDestino(id, COLUNA.JA_E, 'cliente');
    expect(dosValores(leitura).indice).toBe(COLUNA.JA_E);
    expect(leitura.respostas).toEqual(ALGUMAS);
    expect(await fonte.retomar(id)).toEqual(leitura);
  });

  it('a coluna que volta de "não guardar" para "cliente" faz a planilha ser lida de novo, como antes', async () => {
    const { fonte, id } = await lida();
    await fonte.trocarDestino(id, COLUNA.JA_E, 'nao_guardar');
    expect(await fonte.trocarDestino(id, COLUNA.JA_E, 'cliente')).toEqual(
      marcador(id)
    );
    expect(dosValores(await fonte.retomar(id)).indice).toBe(COLUNA.JA_E);
  });

  it('só uma coluna diz quem é cliente: marcar outra devolve a primeira para informação e apaga a escolha', async () => {
    const { fonte, id } = await comAColuna();
    await fonte.responder(id, {
      ...ALGUMAS,
      valores_cliente: { modo: 'preenchidas' },
    });
    const depois = await fonte.trocarDestino(id, COLUNA.SITUACAO, 'cliente');
    expect(
      depois.colunas.filter(c => c.destino === 'cliente').map(c => c.indice)
    ).toEqual([COLUNA.SITUACAO]);
    expect(depois.colunas.find(c => c.indice === COLUNA.JA_E)).toEqual({
      indice: COLUNA.JA_E,
      nome: 'Já é cliente?',
      destino: 'informacao',
      campo: { nome: 'Já é cliente?', para_que_serve: '' },
    });
    expect(depois.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
    });
    expect(dosValores(depois).coluna).toBe('Situação');
    expect(depois.resumo.clientes).toBe(0);
  });

  // O servidor corta o valor em 120 caracteres; a planilha de exemplo não tem
  // nenhum maior.
  it('nenhum valor passa de 120 caracteres', async () => {
    const colunas = [COLUNA.JA_E, COLUNA.SITUACAO, COLUNA.ANIVERSARIO];
    const perguntas = await Promise.all(
      colunas.map(async coluna => {
        esquecerMemoriaDaDemo();
        return dosValores((await comAColuna(coluna)).leitura);
      })
    );
    const valores = perguntas.flatMap(pergunta => pergunta.valores);
    expect(valores.every(({ valor }) => valor.length <= 120)).toBe(true);
  });
});

describe('demonstração: responder com os valores', () => {
  it('os valores marcados viram cliente: nos exemplos e na conta do resumo', async () => {
    const { fonte, id, leitura } = await comAColuna();
    const chaves = [
      chaveDe(leitura, 'Sim'),
      chaveDe(leitura, 'Sim, desde 2019'),
    ];
    const depois = await fonte.responder(id, {
      ...ALGUMAS,
      valores_cliente: { modo: 'valores', chaves },
    });
    expect(depois.respostas).toEqual({
      ...ALGUMAS,
      valores_cliente: { modo: 'valores', chaves },
    });
    // Marina ("Sim, desde 2019") e Sofia ("Sim"); Otávio diz "Não".
    expect(depois.exemplos.map(e => e.cliente)).toEqual([true, false, true]);
    expect(depois.resumo.clientes).toBe(110);
    expect(dosValores(depois)).toEqual(dosValores(leitura));
  });

  it('"toda linha com algo escrito" marca quem tem a célula preenchida', async () => {
    const { fonte, id } = await comAColuna(COLUNA.ANIVERSARIO);
    const depois = await fonte.responder(id, {
      clientes: 'algumas',
      colunaCliente: COLUNA.ANIVERSARIO,
      valores_cliente: { modo: 'preenchidas' },
    });
    expect(depois.respostas.valores_cliente).toEqual({ modo: 'preenchidas' });
    // A terceira pessoa de exemplo não tem aniversário na planilha.
    expect(depois.exemplos.map(e => e.cliente)).toEqual([true, true, false]);
    expect(depois.resumo.clientes).toBe(dosValores(depois).preenchidas);
  });

  it('vale sozinha, sem repetir a resposta de "São clientes?"', async () => {
    const { fonte, id, leitura } = await comAColuna();
    const depois = await fonte.responder(id, {
      valores_cliente: { modo: 'valores', chaves: [chaveDe(leitura, 'Sim')] },
    });
    expect(depois.respostas.clientes).toBe('algumas');
    expect(depois.resumo.clientes).toBe(96);
  });

  it('a conta de clientes nunca passa de quantas pessoas entram', async () => {
    const { fonte, id } = await comAColuna();
    const depois = await fonte.responder(id, {
      ...ALGUMAS,
      valores_cliente: { modo: 'preenchidas' },
    });
    expect(depois.resumo.clientes).toBeLessThanOrEqual(depois.resumo.entram);
    expect(depois.resumo.clientes).toBe(192);
  });

  it('trocar a coluna que diz quem é cliente apaga a escolha', async () => {
    const { fonte, id, leitura } = await comAColuna();
    await fonte.responder(id, {
      ...ALGUMAS,
      valores_cliente: { modo: 'valores', chaves: [chaveDe(leitura, 'Sim')] },
    });
    const trocada = await fonte.responder(id, {
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
    });
    expect(trocada.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
    });
    expect(dosValores(trocada).coluna).toBe('Situação');
    expect(trocada.resumo.clientes).toBe(0);
  });

  // Depois de consertar ou deixar uma linha de fora, a leitura volta com a
  // conta de clientes de agora (no servidor, `clientes` ao lado de `entram`).
  it('deixar uma linha de fora e voltar atrás acertam a conta de clientes junto com quem entra', async () => {
    const { fonte, id } = await lida();
    const todas = await fonte.responder(id, { clientes: 'sim_todas' });
    expect(todas.resumo.clientes).toBe(todas.resumo.entram);
    const consertada = await fonte.consertar(id, 14, '(11) 97380-0014');
    expect(consertada.resumo.entram).toBe(todas.resumo.entram + 1);
    expect(consertada.resumo.clientes).toBe(consertada.resumo.entram);
    const deFora = await fonte.deixarDeFora(id, 14);
    expect(deFora.resumo.clientes).toBe(todas.resumo.entram);
    const reaberta = await fonte.reabrir(id, 14);
    expect(reaberta.resumo.clientes).toBe(reaberta.resumo.entram);
  });

  it('tirar a coluna de "cliente" pela tela das colunas apaga a escolha e a pergunta', async () => {
    const { fonte, id } = await comAColuna();
    await fonte.responder(id, {
      ...ALGUMAS,
      valores_cliente: { modo: 'preenchidas' },
    });
    const depois = await fonte.trocarDestino(id, COLUNA.JA_E, 'informacao');
    expect(dosValores(depois)).toBeUndefined();
    expect(depois.respostas).toEqual({});
    expect(depois.resumo.clientes).toBe(0);
  });
});

describe('demonstração: as recusas da pergunta dos valores', () => {
  it.each([
    ['o modo que não existe', { modo: 'todos' }],
    ['nenhuma chave marcada', { modo: 'valores', chaves: [] }],
    ['sem a lista de chaves', { modo: 'valores' }],
    ['a chave que não é da coluna', { modo: 'valores', chaves: ['outra'] }],
  ])('%s é `resposta_desconhecida`', async (_nome, valores) => {
    const { fonte, id, leitura } = await comAColuna();
    const falha = await fonte
      .responder(id, { ...ALGUMAS, valores_cliente: valores })
      .catch(recusada => recusada);
    expect(falha.name).toBe('TELA_DESATUALIZADA');
    expect(codigoDa(falha)).toBe('resposta_desconhecida');
    // A recusa não deixa nada do pedido guardado.
    expect(await fonte.retomar(id)).toEqual(leitura);
  });

  it('a chave de um valor de outra coluna não vale', async () => {
    const daSituacao = await comAColuna(COLUNA.SITUACAO);
    const chaveDaSituacao = chaveDe(daSituacao.leitura, 'Cliente');
    esquecerMemoriaDaDemo();
    const { fonte, id } = await comAColuna();
    const falha = await fonte
      .responder(id, {
        ...ALGUMAS,
        valores_cliente: { modo: 'valores', chaves: [chaveDaSituacao] },
      })
      .catch(recusada => recusada);
    expect(codigoDa(falha)).toBe('resposta_desconhecida');
  });

  // A pessoa ainda não viu os valores da coluna nova: a tela manda a troca da
  // coluna primeiro e a escolha dos valores depois.
  it('os valores marcados no mesmo pedido que troca a coluna são `resposta_desconhecida`, mesmo com chave da coluna nova', async () => {
    const daSituacao = await comAColuna(COLUNA.SITUACAO);
    const chaveDaSituacao = chaveDe(daSituacao.leitura, 'Cliente');
    esquecerMemoriaDaDemo();
    const { fonte, id, leitura } = await comAColuna();
    const falha = await fonte
      .responder(id, {
        clientes: 'algumas',
        colunaCliente: COLUNA.SITUACAO,
        valores_cliente: { modo: 'valores', chaves: [chaveDaSituacao] },
      })
      .catch(recusada => recusada);
    expect(falha.name).toBe('TELA_DESATUALIZADA');
    expect(codigoDa(falha)).toBe('resposta_desconhecida');
    expect(await fonte.retomar(id)).toEqual(leitura);
  });

  it('os valores marcados no mesmo pedido que diz a coluna pela primeira vez também são recusados', async () => {
    const comColuna = await comAColuna();
    const chave = chaveDe(comColuna.leitura, 'Sim');
    esquecerMemoriaDaDemo();
    const { fonte, id } = await lida();
    const falha = await fonte
      .responder(id, {
        ...ALGUMAS,
        valores_cliente: { modo: 'valores', chaves: [chave] },
      })
      .catch(recusada => recusada);
    expect(codigoDa(falha)).toBe('resposta_desconhecida');
  });

  it('"toda linha com algo escrito" no mesmo pedido que troca a coluna é aceito', async () => {
    const { fonte, id } = await comAColuna();
    const depois = await fonte.responder(id, {
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      valores_cliente: { modo: 'preenchidas' },
    });
    expect(depois.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      valores_cliente: { modo: 'preenchidas' },
    });
    expect(dosValores(depois).coluna).toBe('Situação');
  });

  it('mandar os valores sem haver coluna "cliente" é `pergunta_desconhecida`', async () => {
    const { fonte, id } = await lida();
    const falha = await fonte
      .responder(id, { valores_cliente: { modo: 'preenchidas' } })
      .catch(recusada => recusada);
    expect(falha.name).toBe('TELA_DESATUALIZADA');
    expect(codigoDa(falha)).toBe('pergunta_desconhecida');
  });
});

describe('demonstração: trazer não adivinha quem é cliente', () => {
  it('com a pergunta sem resposta, recusa com `falta_valores_cliente` e não traz', async () => {
    const { fonte, id } = await comAColuna();
    await expect(fonte.trazer(id)).rejects.toMatchObject({
      name: 'FALTA_VALORES_CLIENTE',
    });
    const historico = await fonte.historico();
    expect(historico.some(lista => lista.situacao === 'trazendo')).toBe(false);
  });

  it('com a resposta, traz', async () => {
    const { fonte, id } = await comAColuna();
    await fonte.responder(id, {
      ...ALGUMAS,
      valores_cliente: { modo: 'preenchidas' },
    });
    expect(await fonte.trazer(id)).toEqual({
      trazidaId: expect.any(String),
    });
  });

  it('sem coluna "cliente", traz como antes', async () => {
    const { fonte, id } = await lida();
    expect(await fonte.trazer(id)).toEqual({ trazidaId: expect.any(String) });
  });
});
