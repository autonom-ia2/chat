import { ACOES_DO_HEROI, escolherFrase } from '../../lista/fraseDoHeroi';
import { falouHa } from '../../lista/tempoRelativo';
import { formatarTelefone } from '../../lista/telefone';
import { contaDaMensagem } from '../../lista/quemFicaDeFora';
import {
  FILTROS_VAZIOS,
  contarFiltros,
  pessoaPassaNosFiltros,
} from '../../lista/filtros';

// As funções puras da lista de Relacionamentos (#2894).
const HEROI = 'RELACIONAMENTOS.LISTA.HEROI';

describe('escolherFrase (a frase do dia do herói)', () => {
  it('conta vazia: convida a trazer a lista e não repete o botão no canto', () => {
    const frase = escolherFrase({
      total: 0,
      clientes: 0,
      sumiu_1_a_3_meses: 0,
    });
    expect(frase.id).toBe('vazia');
    expect(frase.partes).toEqual([{ chave: `${HEROI}.VAZIA` }]);
    expect(frase.principal.acao).toBe(ACOES_DO_HEROI.TRAZER);
    expect(frase.mostraTrazerDiscreto).toBe(false);
  });

  it('há quem sumiu: chama a ver quem sumiu, e "trazer" fica discreto', () => {
    const frase = escolherFrase({
      total: 280,
      clientes: 120,
      sumiu_1_a_3_meses: 42,
    });
    expect(frase.id).toBe('sumiram');
    expect(frase.partes).toEqual([{ chave: `${HEROI}.SUMIRAM`, count: 42 }]);
    expect(frase.principal).toEqual({
      rotulo: `${HEROI}.VER_QUEM_SUMIU`,
      acao: ACOES_DO_HEROI.VER_GRUPO,
      grupo: 'sumiu_1_a_3_meses',
    });
    expect(frase.mostraTrazerDiscreto).toBe(true);
  });

  it('senão: diz quantas pessoas e quantos clientes, e chama a ver clientes', () => {
    const frase = escolherFrase({
      total: 280,
      clientes: 120,
      sumiu_1_a_3_meses: 0,
    });
    expect(frase.id).toBe('resumo');
    expect(frase.partes).toEqual([
      { chave: `${HEROI}.PESSOAS_AQUI`, count: 280 },
      { chave: `${HEROI}.JA_SAO_CLIENTES`, count: 120 },
    ]);
    expect(frase.principal.grupo).toBe('clientes');
    expect(frase.mostraTrazerDiscreto).toBe(true);
  });

  it('sem nenhum cliente, não há o que ver: volta a convidar para trazer', () => {
    const frase = escolherFrase({
      total: 5,
      clientes: 0,
      sumiu_1_a_3_meses: 0,
    });
    expect(frase.partes).toEqual([
      { chave: `${HEROI}.PESSOAS_AQUI`, count: 5 },
    ]);
    expect(frase.principal.acao).toBe(ACOES_DO_HEROI.TRAZER);
    expect(frase.mostraTrazerDiscreto).toBe(false);
  });

  it('a conta vazia vem antes de tudo, e quem sumiu antes do resumo', () => {
    expect(escolherFrase({ total: 0, sumiu_1_a_3_meses: 3 }).id).toBe('vazia');
    expect(
      escolherFrase({ total: 10, clientes: 10, sumiu_1_a_3_meses: 1 }).id
    ).toBe('sumiram');
  });

  it('trata resumo sem campos como conta vazia', () => {
    expect(escolherFrase().id).toBe('vazia');
  });
});

describe('falouHa (tempo relativo)', () => {
  const agora = Date.UTC(2026, 10, 11, 12, 0, 0);
  const horasAtras = horas => agora / 1000 - horas * 3600;
  const diasAtras = dias => horasAtras(dias * 24);
  const LINHA = 'RELACIONAMENTOS.LISTA.LINHA';

  it('nunca conversou quando não há data', () => {
    expect(falouHa(null, agora)).toEqual({ chave: `${LINHA}.NUNCA_CONVERSOU` });
    expect(falouHa(undefined, agora)).toEqual({
      chave: `${LINHA}.NUNCA_CONVERSOU`,
    });
  });

  it('hoje, mesmo com horas de diferença, e data no futuro', () => {
    expect(falouHa(horasAtras(0), agora).chave).toBe(`${LINHA}.FALOU_HOJE`);
    expect(falouHa(horasAtras(23), agora).chave).toBe(`${LINHA}.FALOU_HOJE`);
    expect(falouHa(horasAtras(-5), agora).chave).toBe(`${LINHA}.FALOU_HOJE`);
  });

  it('ontem: de 1 dia até antes de 2', () => {
    expect(falouHa(horasAtras(24), agora).chave).toBe(`${LINHA}.FALOU_ONTEM`);
    expect(falouHa(horasAtras(47), agora).chave).toBe(`${LINHA}.FALOU_ONTEM`);
  });

  it('há N dias, de 2 a 29', () => {
    expect(falouHa(diasAtras(2), agora)).toEqual({
      chave: `${LINHA}.FALOU_HA_DIAS`,
      count: 2,
    });
    expect(falouHa(diasAtras(29), agora)).toEqual({
      chave: `${LINHA}.FALOU_HA_DIAS`,
      count: 29,
    });
  });

  it('há N meses, de 30 dias em diante', () => {
    expect(falouHa(diasAtras(30), agora)).toEqual({
      chave: `${LINHA}.FALOU_HA_MESES`,
      count: 1,
    });
    expect(falouHa(diasAtras(59), agora).count).toBe(1);
    expect(falouHa(diasAtras(60), agora).count).toBe(2);
    expect(falouHa(diasAtras(400), agora).count).toBe(13);
  });
});

describe('formatarTelefone', () => {
  it('formata celular do Brasil como +55 11 91031-0001', () => {
    expect(formatarTelefone('+5511910310001')).toBe('+55 11 91031-0001');
  });

  it('formata fixo do Brasil', () => {
    expect(formatarTelefone('+551133334444')).toBe('+55 11 3333-4444');
  });

  it('aceita o número já com pontuação', () => {
    expect(formatarTelefone('+55 (11) 91031-0001')).toBe('+55 11 91031-0001');
  });

  it('devolve como veio o que não é telefone do Brasil', () => {
    expect(formatarTelefone('+14155550123')).toBe('+14155550123');
    expect(formatarTelefone('1234')).toBe('1234');
  });

  it('devolve vazio sem telefone', () => {
    expect(formatarTelefone(null)).toBe('');
    expect(formatarTelefone('')).toBe('');
  });
});

describe('escolherFrase na aba Empresas', () => {
  const resumo = (sem, total = 38) => ({
    total: 280,
    clientes: 120,
    sumiu_1_a_3_meses: 42,
    empresas: { total, sem_conversa_3_meses: sem },
  });

  it('empresas paradas: frase e botão do grupo sem conversa há 3 meses', () => {
    const frase = escolherFrase(resumo(10), 'empresas');
    expect(frase.partes).toEqual([
      { chave: `${HEROI}.EMPRESAS_SEM_CONVERSA`, count: 10 },
    ]);
    expect(frase.principal.grupo).toBe('sem_conversa_3_meses');
    expect(frase.mostraTrazerDiscreto).toBe(true);
  });

  it('nenhuma parada: só quantas empresas, sem botão de grupo', () => {
    const frase = escolherFrase(resumo(0), 'empresas');
    expect(frase.partes).toEqual([
      { chave: `${HEROI}.EMPRESAS_AQUI`, count: 38 },
    ]);
    expect(frase.principal).toBeNull();
  });

  it('conta sem ninguém continua convidando a trazer a lista, em qualquer aba', () => {
    expect(escolherFrase({ total: 0 }, 'empresas').id).toBe('vazia');
  });
});

describe('contaDaMensagem (quem recebe e quem fica de fora)', () => {
  const comTelefone = id => ({
    id,
    phone_number: '+5511910310001',
    opted_out_at: null,
  });

  it('o exemplo do BLOCO-A: 12 marcadas, 2 de fora (1 pediu para não receber, 1 sem telefone)', () => {
    const marcadas = [
      ...Array.from({ length: 10 }, (_, i) => comTelefone(i)),
      { id: 90, phone_number: '+5511910310002', opted_out_at: 1700000000 },
      { id: 91, phone_number: null, opted_out_at: null },
    ];
    expect(contaDaMensagem(marcadas)).toEqual({
      total: 12,
      recebem: 10,
      fora: 2,
      naoQuer: 1,
      bloqueados: 0,
      semTelefone: 1,
    });
  });

  it('bloqueado também fica de fora, com a precedência do backend: pediu para parar, depois bloqueado, depois sem telefone', () => {
    const conta = contaDaMensagem([
      { id: 1, phone_number: '+5511910310001', blocked: true },
      { id: 2, phone_number: null, blocked: true },
      {
        id: 3,
        phone_number: '+5511910310003',
        blocked: true,
        opted_out_at: 1700000000,
      },
      { id: 4, phone_number: null },
      { id: 5, phone_number: '+5511910310005' },
    ]);
    expect(conta).toEqual({
      total: 5,
      recebem: 1,
      fora: 4,
      naoQuer: 1,
      bloqueados: 2,
      semTelefone: 1,
    });
  });

  it('conta uma vez só quem pediu para parar e também está sem telefone', () => {
    const conta = contaDaMensagem([
      { id: 1, phone_number: null, opted_out_at: 1700000000 },
    ]);
    expect(conta).toMatchObject({
      recebem: 0,
      fora: 1,
      naoQuer: 1,
      semTelefone: 0,
    });
  });

  it('todo mundo recebe quando ninguém tem problema', () => {
    expect(contaDaMensagem([comTelefone(1), comTelefone(2)])).toMatchObject({
      recebem: 2,
      fora: 0,
    });
  });

  it('lista vazia não quebra', () => {
    expect(contaDaMensagem()).toEqual({
      total: 0,
      recebem: 0,
      fora: 0,
      naoQuer: 0,
      bloqueados: 0,
      semTelefone: 0,
    });
  });
});

describe('filtros', () => {
  const agora = Date.UTC(2026, 10, 11);
  const diasAtras = dias => agora / 1000 - dias * 86400;
  const pessoa = {
    company_id: 7,
    labels: ['feira'],
    additional_attributes: { city: 'Santos' },
    created_at: diasAtras(10),
  };

  it('conta só os preenchidos', () => {
    expect(contarFiltros(FILTROS_VAZIOS)).toBe(0);
    expect(contarFiltros({ empresa: 7, cidade: 'Santos' })).toBe(2);
    expect(contarFiltros({ empresa: 0 })).toBe(1);
    expect(contarFiltros()).toBe(0);
  });

  it('sem filtro, todo mundo passa', () => {
    expect(pessoaPassaNosFiltros(pessoa, FILTROS_VAZIOS, agora)).toBe(true);
  });

  it.each([
    [{ empresa: 7 }, true],
    [{ empresa: '7' }, true],
    [{ empresa: 8 }, false],
    [{ etiqueta: 'feira' }, true],
    [{ etiqueta: 'site' }, false],
    [{ cidade: 'Santos' }, true],
    [{ cidade: 'Bauru' }, false],
    [{ chegouEm: 'ultimos_30' }, true],
    [{ chegouEm: 'ultimos_7' }, false],
    [
      {
        empresa: 7,
        etiqueta: 'feira',
        cidade: 'Santos',
        chegouEm: 'ultimos_90',
      },
      true,
    ],
    [{ empresa: 7, cidade: 'Bauru' }, false],
  ])('filtro %j -> %s', (filtros, esperado) => {
    expect(pessoaPassaNosFiltros(pessoa, filtros, agora)).toBe(esperado);
  });

  it('pessoa sem empresa, sem etiqueta e sem cidade não passa nos filtros dela', () => {
    const solta = { company_id: null, created_at: diasAtras(1) };
    expect(pessoaPassaNosFiltros(solta, { empresa: 7 }, agora)).toBe(false);
    expect(pessoaPassaNosFiltros(solta, { etiqueta: 'feira' }, agora)).toBe(
      false
    );
    expect(pessoaPassaNosFiltros(solta, { cidade: 'Santos' }, agora)).toBe(
      false
    );
  });
});
