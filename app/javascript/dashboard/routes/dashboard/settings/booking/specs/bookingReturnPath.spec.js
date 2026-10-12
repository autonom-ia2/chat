import { internalReturnPath } from '../bookingReturnPath';

// `?voltar=` do Agendamento (#1371, #1370): a gaveta do agente manda o
// endereço dela com query, e a volta precisa manter a query inteira.
describe('internalReturnPath', () => {
  it('mantém a query do caminho do agente', () => {
    expect(
      internalReturnPath('/app/accounts/16/agents/8?gaveta=agenda', '16')
    ).toBe('/app/accounts/16/agents/8?gaveta=agenda');
  });

  it('recusa o mesmo caminho em outra conta', () => {
    expect(
      internalReturnPath('/app/accounts/16/agents/8?gaveta=agenda', '17')
    ).toBeNull();
  });
});
