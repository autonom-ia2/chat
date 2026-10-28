import {
  acaoDoCard,
  contagemDoResumo,
  ehMeu,
  grupoDoCard,
  montarGrupos,
} from '../grupos';
import { parametrosDaContagem, parametrosDaLista } from '../parametros';

const EU = 7;
const COLEGA = 9;
const OPCOES = { podePassar: true, podeMexer: true };

const card = (id, mudancas = {}) => ({
  id,
  status: 'open',
  action_group: 'demais',
  owner_id: EU,
  ...mudancas,
});

describe('grupoDoCard', () => {
  it('usa o grupo do servidor no card em andamento e o desfecho no fechado', () => {
    expect(grupoDoCard(card(1, { action_group: 'retorno' }))).toBe('retorno');
    expect(grupoDoCard(card(2, { status: 'won' }))).toBe('ganho');
    expect(grupoDoCard(card(3, { status: 'resolved' }))).toBe('ganho');
    expect(grupoDoCard(card(4, { status: 'cancelled' }))).toBe('perdido');
    expect(grupoDoCard(card(5, { status: 'archived' }))).toBe('arquivado');
  });

  it('cai em "Os demais" quando o grupo não veio (tempo real sem sort=acao)', () => {
    expect(grupoDoCard(card(1, { action_group: undefined }))).toBe('demais');
  });
});

describe('ehMeu (o mesmo critério do mine=true)', () => {
  it('é meu quando sou o dono, ou sem dono e a conversa é minha', () => {
    expect(ehMeu(card(1), EU)).toBe(true);
    expect(
      ehMeu(card(2, { owner_id: null, conversation: { assignee_id: EU } }), EU)
    ).toBe(true);
    expect(ehMeu(card(3, { owner_id: COLEGA }), EU)).toBe(false);
  });

  it('a conversa minha esperando resposta é minha mesmo com outro dono', () => {
    const esperando = card(1, {
      owner_id: COLEGA,
      action_group: 'esperando',
      conversation: { assignee_id: EU },
    });
    expect(ehMeu(esperando, EU)).toBe(true);
  });
});

describe('acaoDoCard — a ação principal de cada grupo', () => {
  it('Esperando: "Responder" só para o cliente meu', () => {
    expect(
      acaoDoCard(card(1, { action_group: 'esperando' }), {
        meuId: EU,
        ...OPCOES,
      })
    ).toBe('responder');
    expect(
      acaoDoCard(
        card(2, {
          action_group: 'esperando',
          owner_id: COLEGA,
          current_responsible: { type: 'agent', id: COLEGA, name: 'Bia' },
        }),
        { meuId: EU, ...OPCOES }
      )
    ).toBe('');
  });

  it('Esperando sem ninguém cuidando: a ação de "Ninguém cuidando"', () => {
    const sozinho = card(3, {
      action_group: 'esperando',
      owner_id: null,
      current_responsible: null,
    });
    expect(acaoDoCard(sozinho, { meuId: EU, ...OPCOES })).toBe('passar');
    expect(
      acaoDoCard(sozinho, { meuId: EU, podePassar: false, podeMexer: true })
    ).toBe('ficar');
    expect(
      acaoDoCard(sozinho, { meuId: EU, podePassar: false, podeMexer: false })
    ).toBe('');
    // Conversa oculta com atendente: alguém cuida, mesmo sem nome.
    expect(
      acaoDoCard(
        { ...sozinho, conversation_hidden: true },
        { meuId: EU, ...OPCOES }
      )
    ).toBe('');
  });

  it('Retornos: "Feito" só com o id do retorno e no cliente meu', () => {
    const retorno = card(1, { action_group: 'retorno', next_follow_up_id: 50 });
    expect(acaoDoCard(retorno, { meuId: EU, ...OPCOES })).toBe('feito');
    expect(
      acaoDoCard(
        { ...retorno, next_follow_up_id: null },
        { meuId: EU, ...OPCOES }
      )
    ).toBe('');
    expect(
      acaoDoCard({ ...retorno, owner_id: COLEGA }, { meuId: EU, ...OPCOES })
    ).toBe('');
  });

  it('Ninguém cuidando: "Passar para alguém" ou, sem poder passar, "Ficar com este cliente"', () => {
    const ninguem = card(1, { action_group: 'ninguem', owner_id: null });
    expect(acaoDoCard(ninguem, { meuId: EU, ...OPCOES })).toBe('passar');
    expect(
      acaoDoCard(ninguem, { meuId: EU, podePassar: false, podeMexer: true })
    ).toBe('ficar');
    expect(
      acaoDoCard(ninguem, { meuId: EU, podePassar: false, podeMexer: false })
    ).toBe('');
  });

  it('Parados: "Combinar retorno" também no cliente de colega (decisão 4)', () => {
    const parado = card(1, { action_group: 'parado', owner_id: COLEGA });
    expect(acaoDoCard(parado, { meuId: EU, ...OPCOES })).toBe('combinar');
  });

  it('Os demais e os fechados: sem ação principal', () => {
    expect(acaoDoCard(card(1), { meuId: EU, ...OPCOES })).toBe('');
    expect(
      acaoDoCard(card(2, { status: 'won' }), { meuId: EU, ...OPCOES })
    ).toBe('');
  });
});

describe('montarGrupos', () => {
  const contagem = {
    esperando: 3,
    retorno: 1,
    ninguem: 0,
    parado: 2,
    demais: 20,
  };
  const cards = [
    card(1, { action_group: 'esperando', owner_id: COLEGA }),
    card(2, { action_group: 'esperando' }),
    card(3, { action_group: 'esperando' }),
    card(4, { action_group: 'retorno', next_follow_up_id: 9 }),
    card(5, { action_group: 'ninguem', owner_id: null }),
    card(6, { action_group: 'demais' }),
  ];
  const montar = (extra = {}) =>
    montarGrupos({
      cards,
      contagem,
      meuId: EU,
      opcoes: OPCOES,
      tomDaLinha: item => (item.id === 4 ? 'vermelho' : ''),
      ...extra,
    });

  it('separa na ordem, com o número do servidor, e esconde o grupo com 0', () => {
    const grupos = montar();
    expect(grupos.map(grupo => [grupo.chave, grupo.conta])).toEqual([
      ['esperando', 3],
      ['retorno', 1],
      ['demais', 20],
    ]);
  });

  it('azul cheio só no primeiro cliente meu com ação', () => {
    const cheios = montar()
      .flatMap(grupo => grupo.linhas)
      .filter(linha => linha.cheio)
      .map(linha => linha.card.id);
    expect(cheios).toEqual([2]);
  });

  it('o grupo fica vermelho quando algum retorno já passou da hora', () => {
    const retorno = montar().find(grupo => grupo.chave === 'retorno');
    expect(retorno.tom.fundo).toBe('bg-n-ruby-3');
    const esperando = montar().find(grupo => grupo.chave === 'esperando');
    expect(esperando.tom.fundo).toBe('bg-n-blue-3');
  });

  it('"Ver só estes" mostra um grupo só', () => {
    expect(montar({ grupoSo: 'retorno' }).map(grupo => grupo.chave)).toEqual([
      'retorno',
    ]);
  });
});

describe('parâmetros da API', () => {
  const base = {
    filtros: { result: 'won', search: 'velho', ownerId: '', stageIds: [] },
    pipelineId: 3,
    statuses: { success: 'won', failure: 'lost' },
    quem: 'todos',
    grupoSo: null,
    busca: '',
  };

  it('Em andamento: sort=acao e result=open; a aba e a busca da Lista nova valem, não as da Lista antiga', () => {
    expect(parametrosDaLista({ ...base, aba: 'aberto' })).toEqual({
      pipeline_id: 3,
      result: 'open',
      sort: 'acao',
    });
  });

  it('"Só meus", "Ver só estes" e a busca', () => {
    expect(
      parametrosDaLista({
        ...base,
        aba: 'aberto',
        quem: 'meus',
        grupoSo: 'parado',
        busca: ' Ana ',
      })
    ).toEqual({
      pipeline_id: 3,
      result: 'open',
      sort: 'acao',
      mine: true,
      action_group: 'parado',
      search: 'Ana',
    });
  });

  it('Ganhos/Perdidos seguem o tipo do funil e ordenam pelo mais recente; Tudo vai sem result', () => {
    const atender = { success: 'resolved', failure: 'cancelled' };
    expect(
      parametrosDaLista({ ...base, aba: 'perdido', statuses: atender })
    ).toMatchObject({ result: 'cancelled', sort: 'updated_at' });
    expect(parametrosDaLista({ ...base, aba: 'tudo' })).not.toHaveProperty(
      'result'
    );
  });

  it('a contagem é sempre dos em andamento, agrupada por ação', () => {
    expect(parametrosDaContagem({ ...base, quem: 'meus', busca: 'x' })).toEqual(
      {
        pipeline_id: 3,
        result: 'open',
        group_by: 'acao',
        mine: true,
        search: 'x',
      }
    );
  });

  it('lê o summaries do servidor', () => {
    expect(
      contagemDoResumo({
        groups: [
          { key: 'esperando', count: 2 },
          { key: 'demais', count: '5' },
        ],
      })
    ).toEqual({ esperando: 2, demais: 5 });
  });
});
