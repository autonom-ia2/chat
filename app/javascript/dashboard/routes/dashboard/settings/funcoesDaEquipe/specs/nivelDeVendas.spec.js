import {
  CRM_EXTRAS_IMPLIED_BY_ADMIN,
  PRESETS,
} from '../../customRoles/permissionMatrix';
import {
  escolherNivelDeVendas,
  nivelDeVendas,
  travaDoTudo,
} from '../nivelDeVendas';
import { ADMIN, CARLA } from './quemMonta';

// #2308, especificação 7.4: o quarto nível é o crm_admin com as seis implicadas, sem R$.
describe('nivelDeVendas', () => {
  it('"Cuida de tudo" acrescenta crm_admin e as 6, e não grava sales_value_view', () => {
    const atendente = PRESETS.AGENT();
    const tudo = escolherNivelDeVendas('tudo', atendente);

    expect(tudo.filter(chave => !atendente.includes(chave))).toEqual([
      'crm_admin',
      ...CRM_EXTRAS_IMPLIED_BY_ADMIN,
    ]);
    expect(tudo).not.toContain('sales_value_view');
    expect(nivelDeVendas(tudo)).toBe('tudo');
  });

  it('sair de "Cuida de tudo" tira o crm_admin e as 6', () => {
    const tudo = escolherNivelDeVendas('tudo', PRESETS.AGENT());
    const mexe = escolherNivelDeVendas('manage', tudo);

    expect(mexe).not.toContain('crm_admin');
    CRM_EXTRAS_IMPLIED_BY_ADMIN.forEach(chave =>
      expect(mexe).not.toContain(chave)
    );
    expect(nivelDeVendas(mexe)).toBe('manage');
    expect(nivelDeVendas(escolherNivelDeVendas('none', tudo))).toBe('none');
  });

  it('travaDoTudo: Carla = DELEGATION; administrador e grant_above_own = nada', () => {
    expect(travaDoTudo(CARLA)).toBe('DELEGATION');
    expect(travaDoTudo(ADMIN)).toBeNull();
    expect(
      travaDoTudo({ ...CARLA, permissions: ['grant_above_own'] })
    ).toBeNull();
  });
});
