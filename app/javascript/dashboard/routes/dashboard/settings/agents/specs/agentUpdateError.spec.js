import { agentUpdateErrorKey } from '../agentUpdateError';

// #2317: a recusa do GrantGuard no agents/update leva o código; a tela de editar diz o motivo em vez do erro genérico.
describe('agentUpdateErrorKey', () => {
  it('says the change is beyond the access for out_of_reach', () => {
    expect(agentUpdateErrorKey({ status: 401, code: 'out_of_reach' })).toBe(
      'AGENT_MGMT.EDIT.API.OUT_OF_REACH'
    );
  });

  it('keeps the generic message for anything else', () => {
    expect(
      agentUpdateErrorKey({
        status: 401,
        code: 'You are not authorized to do this action',
      })
    ).toBe('AGENT_MGMT.EDIT.API.ERROR_MESSAGE');
    expect(agentUpdateErrorKey(undefined)).toBe(
      'AGENT_MGMT.EDIT.API.ERROR_MESSAGE'
    );
  });
});
