import {
  chaveDoGrupo,
  comGrupoDaCarga,
  configDaLista,
  opcoesDeOrganizar,
  organizarDaLista,
  resumoPorChave,
} from '../organizar';
import { montarGruposPor } from '../grupos';
import { parametrosDaLista, parametrosDoResumo } from '../parametros';

const estado = extra => ({
  filtros: {},
  pipelineId: 7,
  aba: 'aberto',
  statuses: { success: 'won', failure: 'lost' },
  quem: 'todos',
  grupoSo: null,
  busca: '',
  organizar: 'acao',
  ...extra,
});

describe('Organizar por (#2379)', () => {
  it('só mostra "Maior valor" para quem vê o valor de venda', () => {
    expect(opcoesDeOrganizar({ podeVerValor: true })).toEqual([
      'acao',
      'etapa',
      'quem_cuida',
      'retorno',
      'valor',
      'parado',
      'nome',
    ]);
    expect(opcoesDeOrganizar({ podeVerValor: false })).not.toContain('valor');
  });

  it('pede ao servidor a ordem escolhida; o padrão continua o de antes', () => {
    expect(parametrosDaLista(estado())).toMatchObject({ sort: 'acao' });
    expect(parametrosDaLista(estado({ aba: 'ganho' }))).toMatchObject({
      sort: 'updated_at',
      direction: 'desc',
    });
    expect(
      parametrosDaLista(estado({ organizar: 'quem_cuida' }))
    ).toMatchObject({ sort: 'quem_cuida' });
    expect(
      parametrosDaLista(estado({ organizar: 'nome', aba: 'perdido' }))
    ).toMatchObject({ sort: 'nome', result: 'lost' });
  });

  it('usa "Ver só estes" só nos grupos de ação', () => {
    expect(parametrosDaLista(estado({ grupoSo: 'retorno' })).action_group).toBe(
      'retorno'
    );
    expect(
      parametrosDaLista(estado({ grupoSo: 'retorno', organizar: 'etapa' }))
    ).not.toHaveProperty('action_group');
  });

  it('pede a contagem e a soma do grupo com o mesmo recorte da lista', () => {
    expect(parametrosDoResumo(estado())).toBeNull();
    expect(parametrosDoResumo(estado({ organizar: 'retorno' }))).toBeNull();
    expect(
      parametrosDoResumo(estado({ organizar: 'etapa', quem: 'meus' }))
    ).toMatchObject({ group_by: 'stage', mine: true, result: 'open' });
    expect(
      parametrosDoResumo(estado({ organizar: 'etapa' }))
    ).not.toHaveProperty('sort');
    expect(
      parametrosDoResumo(estado({ organizar: 'quem_cuida' })).group_by
    ).toBe('quem_cuida');
  });

  it('agrupa pela mesma chave do servidor e mantém o grupo da carga no tempo real', () => {
    const card = comGrupoDaCarga({
      id: 1,
      stage_id: 3,
      current_responsible: { type: 'bot', id: 9, name: 'Bia' },
    });
    expect(chaveDoGrupo('quem_cuida', card)).toBe('bot:9');
    expect(chaveDoGrupo('etapa', card)).toBe('3');
    const depois = { ...card, current_responsible: null, stage_id: 4 };
    expect(chaveDoGrupo('quem_cuida', depois)).toBe('bot:9');
    expect(chaveDoGrupo('quem_cuida', { current_responsible: null })).toBe(
      null
    );
  });

  it('monta os grupos na ordem das linhas, com número e soma do servidor', () => {
    const cards = [
      { id: 1, current_responsible: { type: 'agent', id: 2 } },
      { id: 2, current_responsible: { type: 'agent', id: 2 } },
      { id: 3, current_responsible: null },
    ];
    const resumo = resumoPorChave({
      groups: [
        { key: 'agent:2', count: 12, sum_cents: 5000, currency: 'BRL' },
        { key: null, count: 4, sum_cents: null },
      ],
    });
    const grupos = montarGruposPor({
      cards,
      chaveDoGrupo: card => chaveDoGrupo('quem_cuida', card),
      resumo,
      meuId: 2,
      opcoes: {},
    });
    expect(grupos.map(grupo => [grupo.chave, grupo.conta, grupo.soma])).toEqual(
      [
        ['agent:2', 12, 5000],
        ['', 4, null],
      ]
    );
    expect(grupos.every(grupo => grupo.cabecalho)).toBe(true);

    const unica = montarGruposPor({
      cards,
      chaveDoGrupo: null,
      resumo: {},
      meuId: 2,
      opcoes: {},
    });
    expect(unica).toHaveLength(1);
    expect(unica[0]).toMatchObject({ cabecalho: false });
    expect(unica[0].linhas).toHaveLength(3);
  });
});

describe('Listas guardadas (#2379)', () => {
  it('abre a visualização salva da Lista de sempre com a ordem equivalente', () => {
    const com = config => organizarDaLista(config, { podeVerValor: true });
    expect(com({ group_by: 'stage', sort: null })).toBe('etapa');
    expect(com({ group_by: 'owner' })).toBe('quem_cuida');
    expect(com({ group_by: 'none', sort: { id: 'value', desc: true } })).toBe(
      'valor'
    );
    expect(com({ sort: { id: 'title', desc: false } })).toBe('nome');
    expect(com({ sort: { id: 'followUp' } })).toBe('retorno');
    expect(com({ sort: { id: 'status' } })).toBe('acao');
    expect(com({})).toBe('acao');
    expect(
      organizarDaLista({ sort: { id: 'value' } }, { podeVerValor: false })
    ).toBe('acao');
  });

  it('prefere o que a Lista nova guardou', () => {
    expect(
      organizarDaLista(
        { group_by: 'stage', lista_acao: { organizar: 'parado' } },
        { podeVerValor: true }
      )
    ).toBe('parado');
  });

  it('guarda no formato de sempre, para a lista abrir nas duas', () => {
    const campos = [{ chave: 'situacao', visivel: true }];
    const config = configDaLista({
      base: { filters: { ownerId: 3 }, columns: { columnOrder: [] } },
      organizar: 'etapa',
      campos,
    });
    expect(config).toMatchObject({
      filters: { ownerId: 3 },
      columns: { columnOrder: [] },
      group_by: 'stage',
      sort: null,
      lista_acao: { versao: 1, organizar: 'etapa', campos },
    });
    expect(
      configDaLista({ base: {}, organizar: 'valor', campos }).sort
    ).toEqual({ id: 'value', desc: true });
  });
});
