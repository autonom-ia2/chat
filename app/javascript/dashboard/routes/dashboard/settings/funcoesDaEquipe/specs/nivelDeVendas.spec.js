import { PRESETS } from '../../customRoles/permissionMatrix';
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
      'crm_view_reports',
      'crm_manage_pipelines',
      'crm_manage_ai',
      'crm_export',
      'crm_delete_cards',
      'crm_metas_manage',
    ]);
    expect(tudo).not.toContain('sales_value_view');
    expect(nivelDeVendas(tudo)).toBe('tudo');
  });

  it('sair de "Cuida de tudo" sem saber o antes tira o crm_admin e as 6', () => {
    const tudo = escolherNivelDeVendas('tudo', PRESETS.AGENT());
    expect([...escolherNivelDeVendas('manage', tudo)].sort()).toEqual(
      [...PRESETS.AGENT()].sort()
    );
    expect(nivelDeVendas(escolherNivelDeVendas('none', tudo))).toBe('none');
  });

  it('com o antes, sair de "Cuida de tudo" só tira o que ele trouxe: o Gerente de vendas volta igual', () => {
    const gerente = PRESETS.SALES_MANAGER();
    const tudo = escolherNivelDeVendas('tudo', gerente);
    expect(tudo.filter(chave => !gerente.includes(chave))).toEqual([
      'crm_admin',
      'crm_manage_ai',
      'crm_delete_cards',
    ]);
    const volta = escolherNivelDeVendas('manage', tudo, gerente);
    expect([...volta].sort()).toEqual([...gerente].sort());
  });

  it('travaDoTudo: Carla = DELEGATION; administrador e grant_above_own = nada', () => {
    expect(travaDoTudo(CARLA)).toBe('DELEGATION');
    expect(travaDoTudo(ADMIN)).toBeNull();
    expect(
      travaDoTudo({ ...CARLA, permissions: ['grant_above_own'] })
    ).toBeNull();
  });
});
