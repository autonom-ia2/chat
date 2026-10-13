import { accountZoneLabel } from '../scheduleTime';

// Regra do Rodrigo (13/10/2026): data e hora na tela levam o fuso da conta como
// Configurações > Conta mostra — nem o nome longo do Intl ("Horário Padrão de
// Brasília"), nem o código cru (America/Sao_Paulo).
describe('accountZoneLabel', () => {
  it('shows the zone like the account settings do', () => {
    expect(accountZoneLabel('America/Sao_Paulo')).toBe('America/Sao Paulo');
    expect(accountZoneLabel('America/Argentina/Buenos_Aires')).toBe(
      'America/Argentina/Buenos Aires'
    );
    expect(accountZoneLabel('UTC')).toBe('UTC');
  });
});
