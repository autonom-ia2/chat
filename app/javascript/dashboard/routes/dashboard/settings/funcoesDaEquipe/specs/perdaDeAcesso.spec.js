import {
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { perdasDeAcesso } from '../perdaDeAcesso';

// #2308, especificação 5.F: o que quem já tem a função perde ao salvar uma alteração. Cada perda sai uma vez, na
// ordem do Pode, e uma área só entra quando nenhuma capacidade dela já saiu (a mais específica vence, rodada 3).
const semChave = (permissions, chave) =>
  permissions.filter(item => item !== chave);

describe('perdasDeAcesso', () => {
  it('Contatos de Mexer para Ver: perde mudar os contatos, e a área continua', () => {
    const sdr = PRESETS.SDR();
    const depois = setLevel(moduleByKey('CONTACTS'), 'view', sdr);
    expect(perdasDeAcesso(sdr, depois)).toEqual([{ id: 'MUDAR_CONTATOS' }]);
  });

  it('sem os valores em R$, as metas saem junto (só valem com o R$)', () => {
    const gerente = PRESETS.SALES_MANAGER();
    expect(gerente).toContain('crm_metas_manage');
    expect(
      perdasDeAcesso(gerente, semChave(gerente, 'sales_value_view'))
    ).toEqual([{ id: 'VALORES_EM_RS' }, { id: 'METAS_DO_MES' }]);
  });

  it('a área que só olhava e some sem capacidade própria sai como área', () => {
    const atendente = PRESETS.AGENT();
    expect(
      perdasDeAcesso(atendente, semChave(atendente, 'knowledge_base_view'))
    ).toEqual([{ area: 'KNOWLEDGE_BASE' }]);
  });

  it('Canais de Mexer para Ver: perde mexer nos canais, sem repetir a área', () => {
    expect(perdasDeAcesso(['inbox_manage'], ['inbox_view'])).toEqual([
      { id: 'INBOX_MANAGE' },
    ]);
  });

  it('ver as buscas de todos sai pelo nome', () => {
    expect(
      perdasDeAcesso(
        ['prospecting_manage', 'prospecting_view_all_searches'],
        ['prospecting_manage']
      )
    ).toEqual([{ id: 'BUSCAS_DE_TODOS' }]);
  });

  it('função antiga só com crm_admin: perde cada pedaço das vendas que ele trazia', () => {
    expect(perdasDeAcesso(['crm_admin'], [])).toEqual([
      { id: 'CRIAR_MOVER_VENDAS' },
      { id: 'ARQUIVAR_VENDAS' },
      { id: 'MONTAR_COLUNAS' },
      { id: 'RELATORIOS_DAS_VENDAS' },
      { id: 'EXPORTAR_VENDAS' },
      { id: 'IA_NAS_VENDAS' },
    ]);
  });

  // Rodada 3: Vendedor alterado para ficar como Atendente. Antes saíam "Procurar clientes novos" e "Ver: Clientes
  // novos", a mesma coisa com dois nomes, e o título contava 3.
  it('Vendedor para Atendente: procurar clientes novos sai uma vez, sem repetir a área', () => {
    expect(perdasDeAcesso(PRESETS.SDR(), PRESETS.AGENT())).toEqual([
      { id: 'PROCURAR_CLIENTES' },
      { id: 'MUDAR_CONTATOS' },
    ]);
  });

  it('cada área que some é um item', () => {
    expect(
      perdasDeAcesso(['contact_view', 'campaign_view', 'report_manage'], [])
    ).toEqual([
      { id: 'REPORT_MANAGE' },
      { area: 'CONTACTS' },
      { area: 'CAMPAIGNS' },
    ]);
  });

  it('os relatórios de atendimento saem uma vez só: a capacidade já diz, a área (report_manage é o ver) não repete', () => {
    expect(perdasDeAcesso(['report_manage'], [])).toEqual([
      { id: 'REPORT_MANAGE' },
    ]);
  });

  it('sem mudança, nada se perde', () => {
    expect(perdasDeAcesso(PRESETS.SDR(), PRESETS.SDR())).toEqual([]);
  });
});
