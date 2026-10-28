import {
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { nivelQueFica, perdasDeAcesso } from '../perdaDeAcesso';

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

  // Rodada 4: uma capacidade que sai porque outra maior do Pode depois a cobre não é perda.
  it('Atende as próprias para Atende todas: nada se perde', () => {
    const atendente = PRESETS.AGENT();
    const depois = setLevel(moduleByKey('CONVERSATIONS'), 'all', atendente);
    expect(perdasDeAcesso(atendente, depois)).toEqual([]);
    const lendoColegas = [...atendente, 'conversation_view'];
    expect(perdasDeAcesso(lendoColegas, depois)).toEqual([]);
  });

  it('Só olha as conversas para Atende todas: não perde ler as dos colegas', () => {
    expect(
      perdasDeAcesso(['conversation_view'], ['conversation_manage'])
    ).toEqual([]);
  });

  it('Só olha e move as vendas para Pode mexer: não perde mover', () => {
    expect(
      perdasDeAcesso(
        ['crm_view', 'crm_move_cards'],
        setLevel(moduleByKey('CRM'), 'manage', ['crm_view', 'crm_move_cards'])
      )
    ).toEqual([]);
  });

  it('Financeiro de Ver para Mexer: não perde ver os custos', () => {
    expect(perdasDeAcesso(['financial_view'], ['financial_manage'])).toEqual(
      []
    );
  });

  it('Atende todas para as próprias: perde ler e atender todas, e mais nada', () => {
    const supervisor = PRESETS.SUPERVISOR();
    const depois = setLevel(
      moduleByKey('CONVERSATIONS'),
      'limited',
      supervisor
    );
    expect(perdasDeAcesso(supervisor, depois)).toEqual([
      { id: 'LER_E_ATENDER_TODAS' },
    ]);
  });

  it('sem mudança, nada se perde', () => {
    expect(perdasDeAcesso(PRESETS.SDR(), PRESETS.SDR())).toEqual([]);
  });
});

// Rodada 4 (especificação 5.F): numa queda de nível, a perda diz também o que fica ("só vão olhar os contatos").
describe('nivelQueFica', () => {
  it('Contatos de Mexer para Ver: fica olhando os contatos', () => {
    const sdr = PRESETS.SDR();
    expect(
      nivelQueFica(sdr, setLevel(moduleByKey('CONTACTS'), 'view', sdr))
    ).toEqual({ area: 'CONTACTS', nivel: 'OLHA' });
  });

  it('Atende todas para as próprias: fica atendendo as próprias', () => {
    const supervisor = PRESETS.SUPERVISOR();
    expect(
      nivelQueFica(
        supervisor,
        setLevel(moduleByKey('CONVERSATIONS'), 'limited', supervisor)
      )
    ).toEqual({ area: 'CONVERSATIONS', nivel: 'PROPRIAS' });
  });

  it('Vendas de Pode mexer para Só olha: fica olhando as vendas', () => {
    expect(
      nivelQueFica(['crm_view', 'crm_manage_cards'], ['crm_view'])
    ).toEqual({ area: 'CRM', nivel: 'OLHA' });
  });

  it('a área que some, nada que caiu ou duas que caíram: nada a dizer', () => {
    const sdr = PRESETS.SDR();
    expect(
      nivelQueFica(sdr, setLevel(moduleByKey('CONTACTS'), 'none', sdr))
    ).toBeNull();
    expect(nivelQueFica(['contact_view'], ['contact_manage'])).toBeNull();
    expect(
      nivelQueFica(
        ['contact_manage', 'inbox_manage'],
        ['contact_view', 'inbox_view']
      )
    ).toBeNull();
  });
});
