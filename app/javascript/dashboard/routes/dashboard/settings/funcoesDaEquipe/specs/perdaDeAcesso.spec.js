import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
import {
  MODULES,
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { queMudam } from '../fraseDaFuncao';
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
    const supervisor = PRESETS.SUPERVISOR();
    expect(
      perdasDeAcesso(supervisor, semChave(supervisor, 'automation_view'))
    ).toEqual([{ area: 'AUTOMATIONS' }]);
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

  // Rodada 5: o Supervisor que desce para "Atende as próprias" continua pegando as novas e ajudando pelo link (a
  // prévia diz isso); o que fica não pode dizer "só as próprias".
  it('Supervisor de Atende todas para as próprias: fica com as próprias, as novas e o link', () => {
    const supervisor = PRESETS.SUPERVISOR();
    expect(
      nivelQueFica(
        supervisor,
        setLevel(moduleByKey('CONVERSATIONS'), 'limited', supervisor)
      )
    ).toEqual({ area: 'CONVERSATIONS', nivel: 'PROPRIAS_NOVAS_E_LINK' });
  });

  it.each([
    [['conversation_participating_manage'], 'PROPRIAS_E_LINK'],
    [['conversation_unassigned_manage'], 'PROPRIAS_E_NOVAS'],
    [
      ['conversation_participating_manage', 'conversation_unassigned_manage'],
      'PROPRIAS_NOVAS_E_LINK',
    ],
    [
      ['conversation_participating_manage', 'conversation_view'],
      'PROPRIAS_E_LINK',
    ],
  ])('Atende todas para as próprias (%j): %s', (depois, nivel) => {
    expect(nivelQueFica(['conversation_manage'], depois)).toEqual({
      area: 'CONVERSATIONS',
      nivel,
    });
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

  // Rodada 6 (M1): "só vão olhar" só quando a função, nessa área, não pode mudar mais nada. Vendas em "Só olha" que
  // ainda monta as colunas e usa a IA não "só olha"; a perda continua, sem a frase do que fica.
  it('Vendas para Só olha, ainda montando as colunas e usando a IA: sem "só vão olhar"', () => {
    const extras = ['crm_manage_pipelines', 'crm_manage_ai'];
    expect(
      nivelQueFica(
        ['crm_view', 'crm_manage_cards', ...extras],
        ['crm_view', ...extras]
      )
    ).toBeNull();
  });

  it('Contatos para Ver, ainda exportando: sem "só vão olhar"; sem nada a mais, "só vão olhar"', () => {
    expect(
      nivelQueFica(
        ['contact_manage', 'contact_export'],
        ['contact_view', 'contact_export']
      )
    ).toBeNull();
    expect(nivelQueFica(['contact_manage'], ['contact_view'])).toEqual({
      area: 'CONTACTS',
      nivel: 'OLHA',
    });
  });

  // O que só deixa ver (relatórios e R$ das vendas) não tira o "só olhar".
  it('Vendas para Só olha, ainda vendo os relatórios e os R$: só vão olhar', () => {
    const veem = ['crm_view_reports', 'sales_value_view'];
    expect(
      nivelQueFica(
        ['crm_view', 'crm_manage_cards', ...veem],
        ['crm_view', ...veem]
      )
    ).toEqual({ area: 'CRM', nivel: 'OLHA' });
  });

  // Rodada 5: toda área que pode descer para "só olha" tem a forma minúscula da frase ("só vão olhar as vendas"), nos
  // dois idiomas; uma área nova sem ela mostraria a chave crua. Rodada 6: a forma mora em AREAS.*.NA_FRASE, a mesma da
  // trava do cartão e do título da perda, e toda área a tem.
  it('toda área tem a forma do meio da frase em pt_BR e en', () => {
    [ptBR, en].forEach(idioma => {
      MODULES.forEach(module => {
        expect(
          idioma.FUNCOES_EQUIPE.AREAS[module.key]?.NA_FRASE,
          module.key
        ).toBeTruthy();
      });
    });
  });

  it('toda área que desce para "só olha" tem a forma da frase em pt_BR e en', () => {
    const topo = module => (module.type === 'conversations' ? 'all' : 'manage');
    const descem = MODULES.filter(
      module =>
        nivelQueFica(
          setLevel(module, topo(module), []),
          setLevel(module, 'view', [])
        )?.nivel === 'OLHA'
    ).map(module => module.key);
    expect(descem).toContain('CRM');
    expect(descem).toContain('CONVERSATIONS');
    [ptBR, en].forEach(idioma => {
      descem.forEach(area => {
        expect(idioma.FUNCOES_EQUIPE.AREAS[area].NA_FRASE, area).toBeTruthy();
      });
    });
  });
});

// Rodada 7 (L4): uma regra só para `soVe`: toda capacidade que só deixa ver tem a marca, conferida no servidor. Os
// Relatórios (report_manage) não: também escrevem a nota da avaliação (CsatSurveyResponsePolicy#update?).
describe('o que só deixa ver', () => {
  it.each([
    [
      'Financeiro de mexer para olhar',
      ['financial_manage'],
      ['financial_view'],
      'FINANCE',
    ],
    [
      'Procurar clientes para só ver, com as buscas de todos',
      ['prospecting_manage', 'prospecting_view_all_searches'],
      ['prospecting_view', 'prospecting_view_all_searches'],
      'PROSPECTING',
    ],
  ])('%s: "só vão olhar"', (_, antes, depois, area) => {
    expect(nivelQueFica(antes, depois)).toEqual({ area, nivel: 'OLHA' });
  });

  // Rodada 8 (L5), decisão: baixar um relatório do que já se vê conta como ver (desempenho em PDF/planilha, financeiro
  // em CSV, relatórios das vendas); levar a lista de clientes ou de vendas para fora (exportar) não conta.
  it('baixar um relatório conta como ver; exportar contatos ou vendas não', () => {
    expect(
      queMudam([
        'DESEMPENHO_VIEW',
        'FINANCIAL_VIEW',
        'RELATORIOS_DAS_VENDAS',
        'EXPORTAR_VENDAS',
        'EXPORTAR_CONTATOS',
      ])
    ).toEqual(['EXPORTAR_VENDAS', 'EXPORTAR_CONTATOS']);
  });

  it('marca as que só deixam ver, e só elas', () => {
    expect(
      queMudam([
        'LER_COLEGAS',
        'RELATORIOS_DAS_VENDAS',
        'VALORES_EM_RS',
        'BUSCAS_DE_TODOS',
        'DESEMPENHO_VIEW',
        'FINANCIAL_VIEW',
        'REPORT_MANAGE',
        'FINANCIAL_MANAGE',
      ])
    ).toEqual(['FINANCIAL_MANAGE']);
  });
});
