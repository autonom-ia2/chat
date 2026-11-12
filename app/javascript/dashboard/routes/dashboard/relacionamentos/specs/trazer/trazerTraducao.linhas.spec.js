import {
  erroDaEscrita,
  leituraComProblema,
  leituraDaTela,
} from '../../fonte/trazerTraducao';
import { contarProblemas, resumoDaTela } from '../../trazer/contagem';
const erroHttp = (status, error, extra = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error, ...extra } },
  });

// As linhas como o servidor as devolve (a planilha `com_problemas` do spec).
const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
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

const REPETIDA = {
  linha: 8,
  tipo: 'duplicada',
  nome: 'Ana Outra',
  valor: '11987650001',
  estado: 'aberto',
  outraLinha: 2,
  duplicadas: [
    { linha: 2, telefone: '11987650001', email: 'ana@exemplo.com.br' },
    { linha: 8, telefone: '11987650001', email: '' },
  ],
};

const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'telefone', duvidosa: true },
    {
      indice: 3,
      nome: 'Plano',
      destino: 'informacao',
      campo: { nome: 'Plano', para_que_serve: '' },
    },
  ],
  perguntas: [
    { id: 'clientes' },
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: {},
  resumo: {
    total: 7,
    novas: 2,
    completadas: 0,
    comProblema: 4,
    juntadas: 0,
    entram: 2,
  },
  exemplos: [],
  problemas: [TELEFONE, SEM_NOME, SEM_CONTATO, REPETIDA],
  problemas_total: 4,
  pagina: 1,
  por_pagina: 200,
};

const pronta = (extra = {}) => ({ ...PRONTA, ...extra });

// O telefone da linha 4 valeu, mas a linha também não tinha nome: o servidor
// guarda o telefone e devolve o problema que sobrou.
const SOBROU_O_NOME = {
  linha: 4,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '+5511987650004',
  estado: 'aberto',
};

const daLinha = (leitura, linha) =>
  leitura.problemas.find(problema => problema.linha === linha);

describe('tradução: a linha que o servidor devolve', () => {
  const lida = () => leituraDaTela(PRONTA);

  it('a guardada traz o valor como vai ser gravado', () => {
    const nova = leituraComProblema(lida(), {
      ...TELEFONE,
      estado: 'guardado',
      corrigido: '+5511987650004',
    });
    expect(daLinha(nova, 4)).toStrictEqual({
      ...TELEFONE,
      estado: 'guardado',
      corrigido: '+5511987650004',
    });
  });

  it('ficar com ESTA linha repetida: guardada, com `ficar_com` e sem `corrigido`', () => {
    const nova = leituraComProblema(lida(), {
      ...REPETIDA,
      estado: 'guardado',
      ficar_com: 8,
    });
    expect(daLinha(nova, 8)).toStrictEqual({
      ...REPETIDA,
      estado: 'guardado',
      ficar_com: 8,
    });
  });

  it('ficar com a OUTRA linha: esta fica de fora, sem `ficar_com`', () => {
    const nova = leituraComProblema(lida(), { ...REPETIDA, estado: 'deixado' });
    expect(daLinha(nova, 8)).toStrictEqual({ ...REPETIDA, estado: 'deixado' });
  });

  it.each(['aberto', 'deixado'])(
    'a linha que volta como "%s" perde o `corrigido` e o `ficar_com` que tinha',
    estado => {
      const guardadas = [
        { ...TELEFONE, estado: 'guardado', corrigido: '+5511987650004' },
        { ...REPETIDA, estado: 'guardado', ficar_com: 8 },
      ].reduce(leituraComProblema, lida());
      const depois = [
        { ...TELEFONE, estado },
        { ...REPETIDA, estado },
      ].reduce(leituraComProblema, guardadas);
      expect(daLinha(depois, 4)).toStrictEqual({ ...TELEFONE, estado });
      expect(daLinha(depois, 8)).toStrictEqual({ ...REPETIDA, estado });
    }
  );

  it('o conserto valeu e sobrou outro problema: a linha que volta toma o lugar da antiga, inteira', () => {
    const nova = leituraComProblema(lida(), SOBROU_O_NOME);
    expect(daLinha(nova, 4)).toStrictEqual(SOBROU_O_NOME);
    // Nada do tipo antigo fica para trás (a outra linha, as duas repetidas).
    const eraRepetida = leituraComProblema(lida(), {
      linha: 8,
      tipo: 'telefone',
      nome: 'Ana Outra',
      valor: '(11) 2345',
      estado: 'aberto',
    });
    expect(daLinha(eraRepetida, 8)).not.toHaveProperty('outraLinha');
    expect(daLinha(eraRepetida, 8)).not.toHaveProperty('duplicadas');
    expect(nova.problemas.map(problema => problema.linha)).toEqual([
      4, 6, 7, 8,
    ]);
  });

  it('a leitura diz se o telefone da empresa existe nela; sem o campo, existe', () => {
    expect(leituraDaTela(pronta({ tem_empresa: false })).temEmpresa).toBe(
      false
    );
    expect(leituraDaTela(pronta({ tem_empresa: true })).temEmpresa).toBe(true);
    expect(leituraDaTela(PRONTA).temEmpresa).toBe(true);
  });

  it('a escrita numa linha não mexe no que a leitura dizia do telefone da empresa', () => {
    const sem = leituraDaTela(pronta({ tem_empresa: false }));
    const nova = leituraComProblema(sem, { ...TELEFONE, estado: 'deixado' }, 2);
    expect(nova.temEmpresa).toBe(false);
  });

  it('a leitura entrega as linhas juntadas do resumo', () => {
    const leitura = leituraDaTela(
      pronta({ resumo: { ...PRONTA.resumo, juntadas: 12 } })
    );
    expect(leitura.resumo.juntadas).toBe(12);
  });
});

describe('tradução: as recusas do servidor ganham nome', () => {
  it.each([
    ['sem_contato', 'TROCA_SEM_CONTATO'],
    ['planilha_apagada', 'PLANILHA_APAGADA'],
    ['nada_para_trazer', 'NADA_PARA_TRAZER'],
    ['sem_empresa', 'SEM_EMPRESA'],
    ['leitura_nao_pronta', 'TELA_DESATUALIZADA'],
    ['linha_desconhecida', 'TELA_DESATUALIZADA'],
    ['resposta_desconhecida', 'TELA_DESATUALIZADA'],
    ['pergunta_desconhecida', 'TELA_DESATUALIZADA'],
    ['coluna_desconhecida', 'TELA_DESATUALIZADA'],
    ['destino_desconhecido', 'TELA_DESATUALIZADA'],
  ])('422 `%s` vira %s, com a causa guardada', (codigo, nome) => {
    const falha = erroHttp(422, codigo);
    const erro = erroDaEscrita(falha);
    expect(erro.name).toBe(nome);
    expect(erro.cause).toBe(falha);
  });

  it('o que o servidor não nomeia sobe como veio', () => {
    const caiu = erroHttp(500);
    expect(erroDaEscrita(caiu)).toBe(caiu);
    const outra = erroHttp(422, 'codigo_que_nao_existe');
    expect(erroDaEscrita(outra)).toBe(outra);
  });

  it.each(['formula_phone_number', 'muito_longo'])(
    '`valor_invalido` leva o motivo `%s` em código, como o servidor manda',
    motivo => {
      const falha = erroHttp(422, 'valor_invalido', { motivo });
      const erro = erroDaEscrita(falha);
      expect(erro).toMatchObject({ name: 'VALOR_INVALIDO', motivo });
      expect(erro.cause).toBe(falha);
    }
  );
});

describe('as contas com a linha repetida e as linhas juntadas', () => {
  const lida = () => leituraDaTela(PRONTA);
  // Quantas entram quem diz é o servidor, junto com a linha (`entram`).
  const ficouComEsta = (entram = 2) =>
    leituraComProblema(
      lida(),
      { ...REPETIDA, estado: 'guardado', ficar_com: 8 },
      entram
    );

  it('ficar com ESTA linha: a tela mostra o `entram` que o servidor mandou, sem somar ninguém', () => {
    expect(resumoDaTela(lida()).entram).toBe(2);
    expect(resumoDaTela(ficouComEsta())).toMatchObject({
      entram: 2,
      novas: 2,
      precisamDeVoce: 3,
      deixadas: 0,
    });
    expect(contarProblemas(ficouComEsta().problemas)).toMatchObject({
      guardados: 1,
    });
  });

  it('ficar com a OUTRA linha: esta fica de fora', () => {
    const nova = leituraComProblema(
      lida(),
      { ...REPETIDA, estado: 'deixado' },
      2
    );
    expect(resumoDaTela(nova)).toMatchObject({
      entram: 2,
      novas: 2,
      deixadas: 1,
    });
  });

  it('o conserto de telefone, e-mail ou nome: entra quem o servidor diz, e "novas" não muda', () => {
    const nova = leituraComProblema(
      ficouComEsta(),
      { ...TELEFONE, estado: 'guardado', corrigido: '+5511987650004' },
      3
    );
    expect(resumoDaTela(nova).entram).toBe(3);
    expect(resumoDaTela(nova).novas).toBe(2);
  });

  it('o resumo leva as linhas juntadas; sem o número, zero', () => {
    const com = leituraDaTela(
      pronta({ resumo: { ...PRONTA.resumo, juntadas: 12 } })
    );
    expect(resumoDaTela(com).juntadas).toBe(12);
    expect(resumoDaTela({ resumo: { total: 3 }, problemas: [] }).juntadas).toBe(
      0
    );
  });
});
