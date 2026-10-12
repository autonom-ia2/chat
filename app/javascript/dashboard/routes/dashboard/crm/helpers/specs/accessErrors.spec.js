import { chaveDoErroDeAcesso, semDonosBarrados } from '../accessErrors';

const erro = codigo => ({ response: { data: { error: codigo } } });

describe('accessErrors', () => {
  it('translates the funnel refusals and leaves the rest to the generic alert', () => {
    expect(chaveDoErroDeAcesso(erro('crm.owner_without_funnel'))).toBe(
      'CRM_KANBAN.ACCESS.OWNER_WITHOUT_FUNNEL'
    );
    expect(chaveDoErroDeAcesso(erro('crm.access.card_funnel_required'))).toBe(
      'CRM_KANBAN.ACCESS.CARD_FUNNEL_REQUIRED'
    );
    expect(chaveDoErroDeAcesso(erro('You are not authorized'))).toBeNull();
    expect(chaveDoErroDeAcesso(new Error('network'))).toBeNull();
  });

  it('removes only the blocked owners', () => {
    const owners = [{ id: 1 }, { id: 2 }, { id: 3 }];
    expect(semDonosBarrados(owners, [2])).toEqual([{ id: 1 }, { id: 3 }]);
    expect(semDonosBarrados(owners)).toEqual(owners);
  });
});
