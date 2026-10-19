import {
  CHAVES_DO_LINK,
  CHAVES_DO_MEU_DIA,
  filtroDoMeuDiaPeloLink,
  filtrosDoLink,
  semChaves,
} from './filtrosDoLink';

const EU = 7;

describe('filtrosDoLink (Kanban e Lista, #1883)', () => {
  it('returns null when the link brings no filter', () => {
    expect(filtrosDoLink({}, { currentUserId: EU })).toBeNull();
    expect(
      filtrosDoLink({ pipeline_id: '3', view: 'list' }, { currentUserId: EU })
    ).toBeNull();
  });

  it('reads "parado há mais de 7 dias" with me as the owner', () => {
    expect(
      filtrosDoLink({ stale_days: '7', owner_id: 'me' }, { currentUserId: EU })
    ).toEqual({ staleDays: '7', ownerId: EU });
  });

  it('reads one person as the owner', () => {
    expect(filtrosDoLink({ owner_id: '12' }, { currentUserId: EU })).toEqual({
      ownerId: 12,
    });
  });

  it('reads "ganhos do mês sem responsável"', () => {
    expect(
      filtrosDoLink(
        { result: 'won', closed_in: 'this_month', responsible_kind: 'none' },
        { currentUserId: EU }
      )
    ).toEqual({
      result: 'won',
      closedIn: 'this_month',
      responsibleKind: 'none',
    });
  });

  it('keeps the campaign mark of the link, with the owner', () => {
    expect(
      filtrosDoLink(
        { campaign_source_ids: '120,121', owner_id: 'me' },
        { currentUserId: EU }
      )
    ).toEqual({ campaignSourceIds: ['120', '121'], ownerId: EU });
  });

  it('ignores values the screen does not offer', () => {
    expect(
      filtrosDoLink(
        {
          stale_days: '5',
          owner_id: 'todos',
          result: 'qualquer',
          closed_in: 'last_year',
          responsible_kind: 'alguem',
        },
        { currentUserId: EU }
      )
    ).toBeNull();
    expect(filtrosDoLink({ owner_id: '-3' }, { currentUserId: EU })).toBeNull();
    expect(
      filtrosDoLink({ owner_id: '1.5' }, { currentUserId: EU })
    ).toBeNull();
  });

  it('ignores "me" while the user is unknown', () => {
    expect(filtrosDoLink({ owner_id: 'me' }, { currentUserId: null })).toBe(
      null
    );
  });
});

describe('filtroDoMeuDiaPeloLink (#1883)', () => {
  it('returns null when the link brings no filter', () => {
    expect(filtroDoMeuDiaPeloLink({})).toBeNull();
  });

  it('reads "retornos atrasados da equipe"', () => {
    expect(
      filtroDoMeuDiaPeloLink({ quem: 'todos', tipos: 'lembrete' })
    ).toEqual({ quem: 'todos', tipos: ['lembrete'] });
  });

  it('reads "lembretes de Atender" with the funnel', () => {
    expect(
      filtroDoMeuDiaPeloLink({ quem: 'meus', tipos: 'lembrete', funil: '4' })
    ).toEqual({ quem: 'meus', tipos: ['lembrete'], funil: '4' });
  });

  it('ignores unknown values', () => {
    expect(
      filtroDoMeuDiaPeloLink({ quem: 'ana', tipos: 'tarefa', funil: 'x' })
    ).toBeNull();
    expect(filtroDoMeuDiaPeloLink({ tipos: 'lembrete,tarefa' })).toEqual({
      tipos: ['lembrete'],
    });
  });
});

describe('semChaves', () => {
  it('removes the link keys and keeps the rest', () => {
    expect(
      semChaves(
        { view: 'list', stale_days: '7', pipeline_id: '3' },
        CHAVES_DO_LINK
      )
    ).toEqual({ view: 'list', pipeline_id: '3' });
    expect(semChaves({ quem: 'meus', x: '1' }, CHAVES_DO_MEU_DIA)).toEqual({
      x: '1',
    });
  });
});
