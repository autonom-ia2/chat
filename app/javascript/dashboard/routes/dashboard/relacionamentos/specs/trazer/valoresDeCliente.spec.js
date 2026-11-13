import {
  mudouQuemDizQuemEhCliente,
  perguntaRespondida,
  primeiraSemResposta,
  responderPergunta,
  trocarColunaDeCliente,
} from '../../trazer/respostas';
import {
  alternarPreenchidas,
  alternarValor,
  marcouPreenchidas,
  valorMarcado,
  valoresRespondidos,
} from '../../trazer/valoresDeCliente';

// #2896, E3 — "Quais destes querem dizer cliente?": a resposta da pergunta
// nova, em funções puras. Ela é `{ modo: 'preenchidas' }` (toda linha com algo
// escrito na coluna) ou `{ modo: 'valores', chaves: [...] }` (os valores que a
// pessoa marcou); as duas formas não se misturam.
const PERGUNTA = {
  id: 'valores_cliente',
  coluna: 'Já é cliente?',
  indice: 7,
  preenchidas: 35,
  valores: [
    { chave: 'k-sim', valor: 'Sim', linhas: 12 },
    { chave: 'k-nao', valor: 'Não', linhas: 20 },
  ],
  outros: null,
};
const PREENCHIDAS = { modo: 'preenchidas' };
const comChaves = (...chaves) => ({ modo: 'valores', chaves });

describe('a resposta dos valores que querem dizer cliente', () => {
  it('nada marcado não é resposta; as duas formas são', () => {
    expect(valoresRespondidos(undefined)).toBe(false);
    expect(valoresRespondidos(comChaves())).toBe(false);
    expect(valoresRespondidos({ modo: 'outro' })).toBe(false);
    expect(valoresRespondidos(PREENCHIDAS)).toBe(true);
    expect(valoresRespondidos(comChaves('k-sim'))).toBe(true);
  });

  it('marcar a primeira opção desmarca os valores, e desmarcar volta a nada', () => {
    expect(alternarPreenchidas(undefined)).toEqual(PREENCHIDAS);
    expect(alternarPreenchidas(comChaves('k-sim'))).toEqual(PREENCHIDAS);
    expect(alternarPreenchidas(PREENCHIDAS)).toBeNull();
  });

  it('marcar um valor desmarca a primeira opção e soma aos já marcados', () => {
    expect(alternarValor(undefined, 'k-sim')).toEqual(comChaves('k-sim'));
    expect(alternarValor(PREENCHIDAS, 'k-nao')).toEqual(comChaves('k-nao'));
    expect(alternarValor(comChaves('k-sim'), 'k-nao')).toEqual(
      comChaves('k-sim', 'k-nao')
    );
  });

  it('desmarcar um valor tira só ele; o último desmarcado volta a nada', () => {
    expect(alternarValor(comChaves('k-sim', 'k-nao'), 'k-sim')).toEqual(
      comChaves('k-nao')
    );
    expect(alternarValor(comChaves('k-sim'), 'k-sim')).toBeNull();
  });

  it('não mexe na resposta que recebeu', () => {
    const resposta = comChaves('k-sim');
    alternarValor(resposta, 'k-nao');
    expect(resposta).toEqual(comChaves('k-sim'));
  });

  it('diz o que está marcado', () => {
    expect(marcouPreenchidas(PREENCHIDAS)).toBe(true);
    expect(marcouPreenchidas(comChaves('k-sim'))).toBe(false);
    expect(valorMarcado(comChaves('k-sim'), 'k-sim')).toBe(true);
    expect(valorMarcado(comChaves('k-sim'), 'k-nao')).toBe(false);
    expect(valorMarcado(PREENCHIDAS, 'k-sim')).toBe(false);
  });
});

describe('a pergunta dos valores entre as respostas da tela', () => {
  it('só está respondida com algo marcado', () => {
    expect(perguntaRespondida(PERGUNTA, {})).toBe(false);
    expect(perguntaRespondida(PERGUNTA, { valores_cliente: comChaves() })).toBe(
      false
    );
    expect(perguntaRespondida(PERGUNTA, { valores_cliente: PREENCHIDAS })).toBe(
      true
    );
    expect(
      primeiraSemResposta([{ id: 'clientes' }, PERGUNTA], {
        clientes: 'algumas',
        colunaCliente: 7,
      })
    ).toBe(1);
  });

  it('desmarcar tudo (resposta nula) tira a resposta da tela', () => {
    expect(
      responderPergunta(
        { clientes: 'algumas', colunaCliente: 7, valores_cliente: PREENCHIDAS },
        'valores_cliente',
        null
      )
    ).toEqual({ clientes: 'algumas', colunaCliente: 7 });
  });

  it('mudar a resposta de "São clientes?" apaga os valores marcados', () => {
    const antes = {
      clientes: 'algumas',
      colunaCliente: 7,
      valores_cliente: comChaves('k-sim'),
      telefone: 'da_pessoa',
    };
    expect(responderPergunta(antes, 'clientes', 'sim_todas')).toEqual({
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    // A mesma resposta de novo não apaga nada.
    expect(responderPergunta(antes, 'clientes', 'algumas')).toEqual(antes);
    // Responder outra pergunta também não.
    expect(responderPergunta(antes, 'telefone', 'nao_usar')).toEqual({
      ...antes,
      telefone: 'nao_usar',
    });
  });

  it('trocar a coluna que diz quem é cliente apaga os valores marcados', () => {
    const antes = {
      clientes: 'algumas',
      colunaCliente: 7,
      valores_cliente: comChaves('k-sim'),
    };
    expect(trocarColunaDeCliente(antes, 5)).toEqual({
      clientes: 'algumas',
      colunaCliente: 5,
    });
    expect(trocarColunaDeCliente(antes, 7)).toEqual(antes);
  });
});

// A pergunta dos valores vem do servidor, para a coluna que ELE conhece. Se a
// resposta de "São clientes?" na tela aponta outra coluna (ou nenhuma), a tela
// grava antes de seguir: a pergunta certa só existe depois disso.
describe('a resposta de "São clientes?" mudou quem diz quem é cliente', () => {
  const SO_CLIENTES = [{ id: 'clientes' }];
  const COM_VALORES = [{ id: 'clientes' }, PERGUNTA];

  it('"algumas" com uma coluna que o servidor ainda não conhece', () => {
    expect(
      mudouQuemDizQuemEhCliente(SO_CLIENTES, {
        clientes: 'algumas',
        colunaCliente: 7,
      })
    ).toBe(true);
    expect(
      mudouQuemDizQuemEhCliente(COM_VALORES, {
        clientes: 'algumas',
        colunaCliente: 5,
      })
    ).toBe(true);
  });

  it('a mesma coluna da pergunta que a leitura traz não mudou nada', () => {
    expect(
      mudouQuemDizQuemEhCliente(COM_VALORES, {
        clientes: 'algumas',
        colunaCliente: 7,
      })
    ).toBe(false);
  });

  it('"sim, todas" e "ainda não" só mudam quando a leitura trazia a pergunta', () => {
    expect(
      mudouQuemDizQuemEhCliente(SO_CLIENTES, { clientes: 'sim_todas' })
    ).toBe(false);
    expect(
      mudouQuemDizQuemEhCliente(SO_CLIENTES, { clientes: 'ainda_nao' })
    ).toBe(false);
    expect(
      mudouQuemDizQuemEhCliente(COM_VALORES, { clientes: 'sim_todas' })
    ).toBe(true);
  });

  it('a primeira coluna da planilha (índice 0) vale como coluna', () => {
    expect(
      mudouQuemDizQuemEhCliente(
        [{ id: 'clientes' }, { ...PERGUNTA, indice: 0 }],
        {
          clientes: 'algumas',
          colunaCliente: 0,
        }
      )
    ).toBe(false);
  });
});
