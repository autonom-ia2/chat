import { effectScope } from 'vue';
import { leituraDaTela } from '../../fonte/trazerTraducao';
import { ERROS, useTrazerLista } from '../../trazer/useTrazerLista';
const erroDeNome = (nome, extra = {}) =>
  Object.assign(new Error(nome), { name: nome, ...extra });

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

describe('useTrazerLista: as recusas do servidor', () => {
  const LIDA = leituraDaTela(PRONTA);
  // Sem perguntas a leitura cai direto no Conferir (de onde se traz).
  const SEM_PERGUNTAS = leituraDaTela(pronta({ perguntas: [] }));
  const montar = async (daFonte = {}, lida = LIDA) => {
    const avisar = vi.fn();
    const fonte = { ler: vi.fn(async () => lida), ...daFonte };
    const tela = effectScope().run(() => useTrazerLista({ fonte, avisar }));
    await tela.escolherArquivo({ name: 'a.csv' });
    return { tela, avisar, fonte };
  };

  // A tela desatualizada não é mais uma frase de "atualize a página": a tela lê
  // a leitura de novo sozinha e diz que a lista mudou.
  it.each([
    ['guardar', 'consertar', [4, 'x']],
    ['deixarDeFora', 'deixarDeFora', [4]],
    ['reabrir', 'reabrir', [4]],
    ['trocarDestino', 'trocarDestino', [3, 'cidade']],
  ])(
    '%s com a tela desatualizada lê a leitura de novo e diz que a lista mudou',
    async (acao, daFonte, argumentos) => {
      const retomar = vi.fn(async () => LIDA);
      const { tela, avisar } = await montar({
        [daFonte]: vi.fn().mockRejectedValue(erroDeNome('TELA_DESATUALIZADA')),
        retomar,
      });
      expect(await tela[acao](...argumentos)).toBe(false);
      expect(retomar).toHaveBeenCalledWith(812);
      expect(tela.mudou.value).toBe(true);
      expect(avisar).not.toHaveBeenCalled();
      expect(tela.recusaDoConserto.value).toBeNull();
    }
  );

  it('continuar com a tela desatualizada lê de novo e volta à primeira pergunta sem resposta', async () => {
    const retomar = vi.fn(async () => LIDA);
    const { tela, avisar } = await montar({
      responder: vi.fn().mockRejectedValue(erroDeNome('TELA_DESATUALIZADA')),
      retomar,
    });
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(retomar).toHaveBeenCalledWith(812);
    expect(tela.mudou.value).toBe(true);
    expect(avisar).not.toHaveBeenCalled();
    // As respostas são as que o servidor tem (nenhuma): a primeira pergunta.
    expect(tela.estado.value.pergunta).toBe(0);
  });

  it.each([
    ['SEM_EMPRESA', {}, 'RELACIONAMENTOS_TRAZER.ERROS.SEM_EMPRESA'],
    [
      'VALOR_INVALIDO',
      { motivo: 'muito_longo' },
      'RELACIONAMENTOS_TRAZER.ERROS.MUITO_LONGO',
    ],
    [
      'VALOR_INVALIDO',
      { motivo: 'outro' },
      'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR',
    ],
  ])(
    'trocar a coluna recusada com %s %o avisa a frase certa',
    async (nome, extra, aviso) => {
      const { tela, avisar } = await montar({
        trocarDestino: vi.fn().mockRejectedValue(erroDeNome(nome, extra)),
      });
      expect(await tela.trocarDestino(3, 'telefone_da_empresa')).toBe(false);
      expect(avisar.mock.calls).toEqual([[aviso]]);
    }
  );

  it('responder "é da empresa" sem coluna de empresa avisa a frase própria', async () => {
    const { tela, avisar } = await montar({
      responder: vi.fn().mockRejectedValue(erroDeNome('SEM_EMPRESA')),
    });
    await tela.continuar();
    tela.responder('telefone', 'da_empresa');
    await tela.continuar();
    expect(avisar.mock.calls).toEqual([
      ['RELACIONAMENTOS_TRAZER.ERROS.SEM_EMPRESA'],
    ]);
  });

  it('o valor longo demais num conserto é dito na própria linha', async () => {
    const { tela, avisar } = await montar({
      consertar: vi
        .fn()
        .mockRejectedValue(
          erroDeNome('VALOR_INVALIDO', { motivo: 'muito_longo' })
        ),
    });
    await tela.guardar(6, 'x');
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 6,
      motivo: 'muito_longo',
    });
    expect(avisar).not.toHaveBeenCalled();
  });

  it('a planilha já apagada é dita na própria linha, sem toast', async () => {
    const { tela, avisar } = await montar({
      consertar: vi.fn().mockRejectedValue(erroDeNome('PLANILHA_APAGADA')),
    });
    expect(await tela.guardar(4, '11987650004')).toBe(false);
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 4,
      motivo: 'planilha_apagada',
    });
    expect(avisar).not.toHaveBeenCalled();
  });

  it('trazer recusado (NADA_PARA_TRAZER): fica em conferir, com o erro próprio e sem "tentar de novo"', async () => {
    const trazer = vi.fn().mockRejectedValue(erroDeNome('NADA_PARA_TRAZER'));
    const { tela } = await montar({ trazer }, SEM_PERGUNTAS);
    await tela.trazer();
    expect(tela.erro.value).toBe(ERROS.NADA_PARA_TRAZER);
    expect(tela.ocupado.value).toBe(false);
    await tela.tentarDeNovo();
    expect(trazer).toHaveBeenCalledTimes(1);
  });

  // A conta está desfazendo uma lista: a tela diz para esperar; o botão de
  // trazer segue ligado e é por ele que a pessoa pede de novo.
  it('trazer recusado (DESFAZER_EM_CURSO): fica em conferir, com o erro próprio, e o clique seguinte pede de novo', async () => {
    const trazer = vi.fn().mockRejectedValue(erroDeNome('DESFAZER_EM_CURSO'));
    const { tela } = await montar({ trazer }, SEM_PERGUNTAS);
    await tela.trazer();
    expect(tela.erro.value).toBe(ERROS.DESFAZER_EM_CURSO);
    expect(tela.ocupado.value).toBe(false);
    await tela.tentarDeNovo();
    expect(trazer).toHaveBeenCalledTimes(1);
    await tela.trazer();
    expect(trazer).toHaveBeenCalledTimes(2);
  });

  it('trazer com a tela desatualizada: lê a leitura de novo, diz que mudou e não tenta de novo sozinho', async () => {
    const trazer = vi.fn().mockRejectedValue(erroDeNome('TELA_DESATUALIZADA'));
    const retomar = vi.fn(async () => SEM_PERGUNTAS);
    const { tela } = await montar({ trazer, retomar }, SEM_PERGUNTAS);
    await tela.trazer();
    expect(retomar).toHaveBeenCalledWith(812);
    expect(tela.mudou.value).toBe(true);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.ocupado.value).toBe(false);
    await tela.tentarDeNovo();
    expect(trazer).toHaveBeenCalledTimes(1);
  });

  it('a recusa do trazer some quando a pessoa mexe numa linha', async () => {
    const { tela } = await montar(
      {
        trazer: vi.fn().mockRejectedValue(erroDeNome('NADA_PARA_TRAZER')),
        reabrir: vi.fn(async () => SEM_PERGUNTAS),
      },
      SEM_PERGUNTAS
    );
    await tela.trazer();
    expect(tela.erro.value).toBe(ERROS.NADA_PARA_TRAZER);
    await tela.reabrir(4);
    expect(tela.erro.value).toBe(ERROS.NENHUM);
  });

  it('o erro de trazer que tem "tentar de novo" não some por mexer numa linha', async () => {
    const { tela } = await montar(
      {
        trazer: vi.fn().mockRejectedValue(new Error('caiu')),
        reabrir: vi.fn(async () => SEM_PERGUNTAS),
      },
      SEM_PERGUNTAS
    );
    await tela.trazer();
    await tela.reabrir(4);
    expect(tela.erro.value).toBe(ERROS.TRAZER);
  });
});
