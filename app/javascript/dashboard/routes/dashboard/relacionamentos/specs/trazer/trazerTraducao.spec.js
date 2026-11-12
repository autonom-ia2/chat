import {
  andamentoDaTela,
  colunaPeloIndice,
  corpoDasRespostas,
  corpoDoConserto,
  corpoDoDestino,
  erroDaEscrita,
  erroDaLeitura,
  erroDoEnvio,
  leituraComMaisProblemas,
  leituraComProblema,
  leituraDaTela,
  listaDaTela,
  problemaDaLeitura,
  respostasDaTela,
} from '../../fonte/trazerTraducao';

// A tradução entre o servidor e a tela de "Trazer minha lista" (#2896): funções
// puras. O contrato do servidor está em
// spec/requests/api/v1/accounts/relacionamentos_trazer_spec.rb.
const erroHttp = (status, error, extra = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error, ...extra } },
  });

const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.xlsx',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 2, nome: 'Fone 2', destino: 'telefone', duvidosa: true },
    {
      indice: 6,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: '' },
    },
  ],
  perguntas: [{ id: 'clientes' }, { id: 'telefone', coluna: 'Fone 2' }],
  respostas: {},
  resumo: { total: 200, novas: 180, completadas: 15, comProblema: 5 },
  exemplos: [
    {
      nome: 'Marina Esteveira',
      telefone: '+55 11 94271-0003',
      email: 'marina.esteveira@exemplo.com.br',
      empresa: 'Casa Aurora',
      cliente: false,
    },
  ],
  problemas: [
    {
      linha: 14,
      tipo: 'telefone',
      nome: 'Tadeu Imbirussu',
      valor: '+55 11 9738-0014',
      estado: 'aberto',
    },
  ],
  problemas_total: 5,
  pagina: 1,
  por_pagina: 200,
};

describe('leituraDaTela', () => {
  it('entrega o que a tela lê e deixa de fora a paginação e a situação', () => {
    const leitura = leituraDaTela(PRONTA);
    expect(leitura).toEqual({
      id: 812,
      arquivo: 'Clientes 2025.xlsx',
      valores: 'inteiros',
      temEmpresa: true,
      colunas: PRONTA.colunas,
      perguntas: PRONTA.perguntas,
      respostas: {},
      resumo: PRONTA.resumo,
      exemplos: PRONTA.exemplos,
      problemas: PRONTA.problemas,
      // Quantas linhas precisam da pessoa ao todo (a tela mostra a 1ª página).
      problemasTotal: 5,
    });
  });

  it('sem o total do servidor, valem os problemas que vieram', () => {
    const { problemas_total: _, ...semTotal } = PRONTA;
    expect(leituraDaTela(semTotal).problemasTotal).toBe(1);
  });

  it('devolve cópias: mexer na leitura não mexe na resposta', () => {
    const leitura = leituraDaTela(PRONTA);
    leitura.colunas[0].destino = 'nao_guardar';
    leitura.problemas[0].estado = 'deixado';
    leitura.resumo.total = 0;
    expect(PRONTA.colunas[0].destino).toBe('nome');
    expect(PRONTA.problemas[0].estado).toBe('aberto');
    expect(PRONTA.resumo.total).toBe(200);
  });

  it('o telefone dos exemplos chega do servidor sem formato e sai como a pessoa lê', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      exemplos: [
        { nome: 'Ana', telefone: '+5511987650001', email: '', empresa: '' },
        { nome: 'Bruno', telefone: '', email: 'bruno@exemplo.com.br' },
      ],
    });
    expect(leitura.exemplos.map(exemplo => exemplo.telefone)).toEqual([
      '+55 11 98765-0001',
      '',
    ]);
    expect(leitura.exemplos[1].email).toBe('bruno@exemplo.com.br');
  });

  it('o valor do problema fica como está na planilha', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      problemas: [{ ...PRONTA.problemas[0], valor: '(11) 2345-678' }],
    });
    expect(leitura.problemas[0].valor).toBe('(11) 2345-678');
  });

  it('planilha já apagada chega com os valores mascarados', () => {
    expect(leituraDaTela({ ...PRONTA, valores: 'mascarados' }).valores).toBe(
      'mascarados'
    );
  });
});

// "Mostrar mais": a página seguinte entra depois do que a leitura já tem
// (paginasDeProblemas.spec.js tem a fonte e a tela).
describe('leituraComMaisProblemas', () => {
  const RITA = {
    linha: 37,
    tipo: 'email',
    nome: 'Rita',
    valor: 'rita',
    estado: 'aberto',
  };

  it('soma os problemas da página seguinte, na ordem em que vieram', () => {
    const antes = leituraDaTela(PRONTA);
    const depois = leituraComMaisProblemas(antes, {
      ...PRONTA,
      problemas: [RITA],
      pagina: 2,
    });
    expect(depois.problemas.map(problema => problema.linha)).toEqual([14, 37]);
    expect(depois.problemasTotal).toBe(5);
    expect(antes.problemas).toHaveLength(1);
  });

  it('a linha que a leitura já tem não entra duas vezes, e fica como a tela a tem', () => {
    const antes = leituraComProblema(
      leituraDaTela(PRONTA),
      { ...PRONTA.problemas[0], estado: 'deixado' },
      195
    );
    const depois = leituraComMaisProblemas(antes, {
      ...PRONTA,
      problemas: [PRONTA.problemas[0], RITA],
    });
    expect(depois.problemas.map(problema => problema.linha)).toEqual([14, 37]);
    expect(depois.problemas[0].estado).toBe('deixado');
  });

  it('o total passa a ser o que a página nova diz', () => {
    const depois = leituraComMaisProblemas(leituraDaTela(PRONTA), {
      ...PRONTA,
      problemas: [RITA],
      problemas_total: 2,
    });
    expect(depois.problemasTotal).toBe(2);
  });
});

describe('erroDaLeitura', () => {
  it.each([
    ['vazia', 'PLANILHA_VAZIA'],
    ['sem_contato', 'PLANILHA_SEM_CONTATO'],
    ['leitura', 'LEITURA_FALHOU'],
    ['inventado', 'LEITURA_FALHOU'],
    [undefined, 'LEITURA_FALHOU'],
  ])('leitura que falhou por %s vira %s', (erro, nome) => {
    const falha = erroDaLeitura({ id: 812, situacao: 'falhou', erro });
    expect(falha).toBeInstanceOf(Error);
    expect(falha.name).toBe(nome);
  });
});

describe('erroDoEnvio', () => {
  const recusa = (status, error) =>
    Object.assign(new Error(`Request failed with status code ${status}`), {
      response: { status, data: { error } },
    });

  it.each([
    ['tipo', 'PLANILHA_TIPO'],
    ['arquivo_grande', 'PLANILHA_GRANDE'],
  ])('422 %s vira %s e guarda a causa', (codigo, nome) => {
    const causa = recusa(422, codigo);
    const falha = erroDoEnvio(causa);
    expect(falha.name).toBe(nome);
    expect(falha.cause).toBe(causa);
  });

  it('o que não tem nome sobe como veio', () => {
    const semArquivo = recusa(422, 'arquivo_obrigatorio');
    const caiu = recusa(500);
    expect(erroDoEnvio(semArquivo)).toBe(semArquivo);
    expect(erroDoEnvio(caiu)).toBe(caiu);
  });
});

describe('colunaPeloIndice', () => {
  it('acha a coluna da leitura pelo índice dela na planilha', () => {
    expect(colunaPeloIndice(leituraDaTela(PRONTA), 6).nome).toBe('Situação');
  });

  it('nome repetido ou vazio não confunde: quem identifica é o índice', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      colunas: [
        { indice: 0, nome: 'Telefone', destino: 'telefone' },
        { indice: 3, nome: 'Telefone', destino: 'informacao' },
        { indice: 4, nome: '', destino: 'informacao' },
      ],
    });
    expect(colunaPeloIndice(leitura, 3).destino).toBe('informacao');
    expect(colunaPeloIndice(leitura, 4).nome).toBe('');
  });

  it('coluna que não existe dá erro nomeado', () => {
    expect(() => colunaPeloIndice(leituraDaTela(PRONTA), 9)).toThrow(
      expect.objectContaining({ name: 'COLUNA_NAO_ENCONTRADA' })
    );
    expect(() => colunaPeloIndice(leituraDaTela(PRONTA), 'Nome')).toThrow(
      expect.objectContaining({ name: 'COLUNA_NAO_ENCONTRADA' })
    );
  });
});

describe('corpoDoDestino', () => {
  it('manda só o destino', () => {
    expect(corpoDoDestino('nao_guardar')).toStrictEqual({
      destino: 'nao_guardar',
    });
    expect(corpoDoDestino('informacao')).toStrictEqual({
      destino: 'informacao',
    });
  });

  // Fatia 2 — a informação nova leva o nome do campo e o "para que serve".
  it('informação nova leva o nome do campo e o para que serve, sem espaço sobrando', () => {
    expect(
      corpoDoDestino('informacao', {
        nome: ' Vencimento ',
        para_que_serve: ' mês em que o seguro vence ',
      })
    ).toStrictEqual({
      destino: 'informacao',
      nome: 'Vencimento',
      para_que_serve: 'mês em que o seguro vence',
    });
  });

  it('o para que serve é opcional: sem ele vai vazio', () => {
    expect(corpoDoDestino('informacao', { nome: 'Vencimento' })).toStrictEqual({
      destino: 'informacao',
      nome: 'Vencimento',
      para_que_serve: '',
    });
  });

  it('os outros destinos não levam campo nenhum', () => {
    expect(corpoDoDestino('cidade', { nome: 'Cidade' })).toStrictEqual({
      destino: 'cidade',
    });
  });
});

describe('respostas das perguntas', () => {
  it('do servidor para a tela: `coluna_cliente` vira `colunaCliente`', () => {
    expect(
      respostasDaTela({
        clientes: 'algumas',
        coluna_cliente: 6,
        telefone: 'da_pessoa',
      })
    ).toStrictEqual({
      clientes: 'algumas',
      colunaCliente: 6,
      telefone: 'da_pessoa',
    });
  });

  it('sem resposta nenhuma (ou sem o campo) é um objeto vazio', () => {
    expect(respostasDaTela({})).toStrictEqual({});
    expect(respostasDaTela(undefined)).toStrictEqual({});
    expect(
      respostasDaTela({ clientes: null, coluna_cliente: null })
    ).toStrictEqual({});
  });

  it('a primeira coluna da planilha (índice 0) não some', () => {
    expect(
      respostasDaTela({ clientes: 'algumas', coluna_cliente: 0 })
    ).toStrictEqual({ clientes: 'algumas', colunaCliente: 0 });
    expect(
      corpoDasRespostas({ clientes: 'algumas', colunaCliente: 0 })
    ).toStrictEqual({ clientes: 'algumas', coluna_cliente: 0 });
  });

  it('da tela para o servidor: só o que foi respondido', () => {
    expect(
      corpoDasRespostas({ clientes: 'ainda_nao', telefone: 'nao_usar' })
    ).toStrictEqual({ clientes: 'ainda_nao', telefone: 'nao_usar' });
    expect(corpoDasRespostas({ clientes: 'sim_todas' })).toStrictEqual({
      clientes: 'sim_todas',
    });
    expect(corpoDasRespostas({})).toStrictEqual({});
  });

  it('a coluna de cliente só vai quando a resposta é "algumas"', () => {
    expect(
      corpoDasRespostas({ clientes: 'sim_todas', colunaCliente: 6 })
    ).toStrictEqual({ clientes: 'sim_todas' });
  });

  it('a leitura entrega as respostas que o servidor guardou', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      respostas: { clientes: 'algumas', coluna_cliente: 6 },
    });
    expect(leitura.respostas).toStrictEqual({
      clientes: 'algumas',
      colunaCliente: 6,
    });
  });
});

describe('o conserto de uma linha', () => {
  const REPETIDA = {
    linha: 143,
    tipo: 'duplicada',
    nome: 'Paulo Hortêncio',
    valor: 'Paulo Hortêncio',
    outraLinha: 88,
    estado: 'aberto',
  };
  const comRepetida = () =>
    leituraDaTela({ ...PRONTA, problemas: [...PRONTA.problemas, REPETIDA] });

  it('problemaDaLeitura acha o problema pela linha', () => {
    expect(problemaDaLeitura(comRepetida(), 143).tipo).toBe('duplicada');
  });

  it('linha que a leitura não tem dá erro nomeado', () => {
    expect(() => problemaDaLeitura(comRepetida(), 999)).toThrow(
      expect.objectContaining({ name: 'LINHA_NAO_ENCONTRADA' })
    );
  });

  it('telefone, e-mail e nome mandam o valor', () => {
    expect(
      corpoDoConserto(PRONTA.problemas[0], '+5511973800014')
    ).toStrictEqual({ valor: '+5511973800014' });
  });

  it('linha repetida manda com qual linha fica', () => {
    expect(corpoDoConserto(REPETIDA, 88)).toStrictEqual({ ficar_com: 88 });
  });

  // O servidor devolve a linha inteira (trazerTraducao.linhas.spec.js tem os
  // corpos).
  it('a linha que volta toma o lugar da que a leitura tinha', () => {
    const antes = comRepetida();
    const depois = leituraComProblema(antes, {
      ...PRONTA.problemas[0],
      estado: 'guardado',
      corrigido: '+55 11 97380-0014',
    });
    expect(depois.problemas[0]).toStrictEqual({
      ...PRONTA.problemas[0],
      estado: 'guardado',
      corrigido: '+55 11 97380-0014',
    });
    // A outra linha e o resto da leitura ficam como estavam.
    expect(depois.problemas[1]).toStrictEqual(REPETIDA);
    expect(depois.colunas).toStrictEqual(antes.colunas);
    expect(antes.problemas[0].estado).toBe('aberto');
  });

  it('linha que volta a ficar aberta (ou vai para fora) perde o valor corrigido', () => {
    const guardada = leituraComProblema(comRepetida(), {
      ...PRONTA.problemas[0],
      estado: 'guardado',
      corrigido: '+55 11 97380-0014',
    });
    const reaberta = leituraComProblema(guardada, PRONTA.problemas[0]);
    expect(reaberta.problemas[0]).toStrictEqual(PRONTA.problemas[0]);
    const deixada = leituraComProblema(guardada, {
      ...PRONTA.problemas[0],
      estado: 'deixado',
    });
    expect(deixada.problemas[0]).toStrictEqual({
      ...PRONTA.problemas[0],
      estado: 'deixado',
    });
  });

  it('o 422 `valor_invalido` vira erro nomeado, com o motivo', () => {
    const falha = erroHttp(422, 'valor_invalido', {
      motivo: 'invalid_brazilian_mobile_number',
    });
    const erro = erroDaEscrita(falha);
    expect(erro).toMatchObject({
      name: 'VALOR_INVALIDO',
      motivo: 'invalid_brazilian_mobile_number',
    });
    expect(erro.cause).toBe(falha);
  });

  it('sem motivo, o erro nomeado vem com o motivo vazio', () => {
    expect(erroDaEscrita(erroHttp(422, 'valor_invalido')).motivo).toBe('');
  });

  // As recusas que o servidor nomeia estão em trazerTraducao.linhas.spec.js.
  it('o que o servidor não nomeia sobe como veio', () => {
    const outro = erroHttp(422, 'codigo_que_nao_existe');
    expect(erroDaEscrita(outro)).toBe(outro);
    const caiu = erroHttp(500);
    expect(erroDaEscrita(caiu)).toBe(caiu);
  });
});

describe('erroDaEscrita', () => {
  it('tirar a última coluna de contato (422 `sem_contato`) ganha nome', () => {
    const falha = erroHttp(422, 'sem_contato');
    const erro = erroDaEscrita(falha);
    expect(erro.name).toBe('TROCA_SEM_CONTATO');
    expect(erro.cause).toBe(falha);
  });

  it('o que o servidor não nomeia sobe como veio', () => {
    const outra = erroHttp(422, 'codigo_que_nao_existe');
    expect(erroDaEscrita(outra)).toBe(outra);
  });
});

// Responder e trocar a coluna devolvem a leitura inteira (como o GET): ela toma
// o lugar da que a tela tinha, com o que o servidor guardou de cada linha.
describe('a leitura inteira que volta de uma escrita', () => {
  it('vale o que o servidor devolve: colunas, respostas, exemplos e o estado de cada linha', () => {
    const depois = leituraDaTela({
      ...PRONTA,
      colunas: [{ indice: 0, nome: 'Nome', destino: 'nome' }],
      respostas: { clientes: 'sim_todas' },
      exemplos: [{ ...PRONTA.exemplos[0], cliente: true }],
      problemas: [
        {
          ...PRONTA.problemas[0],
          estado: 'guardado',
          corrigido: '+55 11 97380-0014',
        },
      ],
    });
    expect(depois.colunas).toHaveLength(1);
    expect(depois.respostas).toStrictEqual({ clientes: 'sim_todas' });
    expect(depois.exemplos[0].cliente).toBe(true);
    expect(depois.problemas[0]).toMatchObject({
      estado: 'guardado',
      corrigido: '+55 11 97380-0014',
    });
    expect(depois.arquivo).toBe('Clientes 2025.xlsx');
  });
});

describe('listaDaTela', () => {
  const DO_SERVIDOR = {
    id: 812,
    arquivo: 'Clientes 2025.xlsx',
    quando: '2026-11-08T14:03:00Z',
    quem: 'Marina Pavanelli',
    total: 195,
    situacao: 'pronto',
    porcentagem: 100,
    pode_tentar: false,
  };

  it('traduz a data para milissegundos, `pode_tentar` para `podeTentar` e `pode_desfazer` para `podeDesfazer`', () => {
    expect(listaDaTela({ ...DO_SERVIDOR, pode_desfazer: true })).toEqual({
      id: 812,
      arquivo: 'Clientes 2025.xlsx',
      quando: Date.UTC(2026, 10, 8, 14, 3),
      quem: 'Marina Pavanelli',
      total: 195,
      situacao: 'pronto',
      porcentagem: 100,
      podeTentar: false,
      podeDesfazer: true,
    });
  });

  // Quem diz se dá para desfazer é o servidor, não a situação.
  it.each([
    ['pronto', true],
    ['falhou', true],
    ['desfazendo', true],
    ['desfazendo', false],
    ['pronto', false],
  ])(
    'lista %s com `pode_desfazer` %s: `podeDesfazer` igual',
    (situacao, pode) => {
      const lista = listaDaTela({
        ...DO_SERVIDOR,
        situacao,
        pode_desfazer: pode,
      });
      expect(lista.podeDesfazer).toBe(pode);
    }
  );

  it('sem `pode_desfazer` não pode desfazer', () => {
    expect(listaDaTela(DO_SERVIDOR).podeDesfazer).toBe(false);
  });

  it.each([
    ['pronto', 'pronto'],
    ['trazendo', 'trazendo'],
    ['desfeito', 'desfeito'],
    ['falhou', 'falhou'],
    ['desfazendo', 'desfazendo'],
  ])('situação %s chega à tela como %s', (doServidor, daTela) => {
    expect(listaDaTela({ ...DO_SERVIDOR, situacao: doServidor }).situacao).toBe(
      daTela
    );
  });

  it('lista que falhou e pode continuar diz `podeTentar`', () => {
    const lista = listaDaTela({
      ...DO_SERVIDOR,
      situacao: 'falhou',
      pode_tentar: true,
    });
    expect(lista).toMatchObject({ situacao: 'falhou', podeTentar: true });
  });

  it('lista de quem já saiu da conta chega sem o nome de quem trouxe', () => {
    expect(listaDaTela({ ...DO_SERVIDOR, quem: null }).quem).toBe('');
  });

  it('sem `pode_tentar` não pode tentar', () => {
    expect(listaDaTela({ id: 9, situacao: 'falhou' }).podeTentar).toBe(false);
  });
});

describe('andamentoDaTela', () => {
  it('entrega porcentagem, situação e os números', () => {
    expect(
      andamentoDaTela({
        porcentagem: 42,
        situacao: 'trazendo',
        total: 195,
        novas: 70,
        completadas: 12,
      })
    ).toEqual({
      porcentagem: 42,
      situacao: 'trazendo',
      total: 195,
      novas: 70,
      completadas: 12,
    });
  });

  it('`desfazendo` chega como o servidor diz', () => {
    expect(andamentoDaTela({ situacao: 'desfazendo' }).situacao).toBe(
      'desfazendo'
    );
  });
});
