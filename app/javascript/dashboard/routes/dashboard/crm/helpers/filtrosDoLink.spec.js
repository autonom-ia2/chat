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

  it('reads "retornos atrasados de uma pessoa" (#1883, opção 2)', () => {
    expect(
      filtrosDoLink(
        { follow_up_status: 'overdue', owner_id: '12' },
        { currentUserId: EU }
      )
    ).toEqual({ followUpStatus: 'overdue', ownerId: 12 });
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
          follow_up_status: 'ontem',
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

describe('filtrosDoLink — o "Ver" de Números › Origens (#2001, F6)', () => {
  it('reads the month, the origin and the ad, with "Todos" as the result', () => {
    expect(
      filtrosDoLink(
        { result: 'todos', entrou_em: '2026-10', origem: 'anuncio_meta' },
        { currentUserId: EU }
      )
    ).toEqual({ result: '', entrouEm: '2026-10', origem: 'anuncio_meta' });
    expect(
      filtrosDoLink(
        { entrou_em: '2026-09', anuncio: '120210000000101' },
        { currentUserId: EU }
      )
    ).toEqual({ entrouEm: '2026-09', anuncio: '120210000000101' });
  });

  it('drops an unknown origin, an ad id with letters and a broken month', () => {
    expect(
      filtrosDoLink(
        {
          origem: 'indicacao',
          anuncio: '12a',
          entrou_em: '2026-13',
        },
        { currentUserId: EU }
      )
    ).toBeNull();
    expect(
      filtrosDoLink({ entrou_em: 'this_month' }, { currentUserId: EU })
    ).toBeNull();
    expect(CHAVES_DO_LINK).toEqual(
      expect.arrayContaining(['origem', 'anuncio', 'entrou_em'])
    );
  });
});
