import { keyLockReason } from 'dashboard/helper/peopleAccess';
import { motivoDasChaves, motivoDaTrava } from '../motivoDaTrava';
import { ADMIN, CARLA } from './quemMonta';

// #2308, especificação 7.3: DELEGATION vence MISSING, chave e dependência testadas separadamente.
describe('motivoDaTrava', () => {
  it('Carla + metas do mês = DELEGATION (o R$ é de delegação)', () => {
    expect(motivoDaTrava(CARLA, 'crm_metas_manage')).toBe('DELEGATION');
    // O keyLockReason de hoje acha primeiro a própria chave e diria MISSING: é o que este helper corrige.
    expect(keyLockReason(CARLA, 'crm_metas_manage')).toBe('MISSING');
  });

  it('Carla + levar as vendas para uma planilha = MISSING', () => {
    expect(motivoDaTrava(CARLA, 'crm_export')).toBe('MISSING');
  });

  it('o que a Carla tem não trava; o administrador nunca trava', () => {
    expect(motivoDaTrava(CARLA, 'campaign_send')).toBeNull();
    expect(motivoDaTrava(ADMIN, 'crm_metas_manage')).toBeNull();
    expect(motivoDaTrava(ADMIN, 'financial_manage')).toBeNull();
  });

  it('num grupo, uma de delegação basta para DELEGATION', () => {
    expect(motivoDasChaves(CARLA, ['crm_export', 'meta_ads_manage'])).toBe(
      'DELEGATION'
    );
    expect(motivoDasChaves(CARLA, ['crm_export', 'insurance_view'])).toBe(
      'MISSING'
    );
    expect(motivoDasChaves(CARLA, ['crm_view', 'campaign_send'])).toBeNull();
  });
});
