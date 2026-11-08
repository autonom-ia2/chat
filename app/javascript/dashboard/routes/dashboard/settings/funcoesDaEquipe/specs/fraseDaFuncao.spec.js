import {
  PRESETS,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../../customRoles/permissionMatrix';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
import {
  contidasEm,
  cuidadosDaFuncao,
  fraseDaFuncao,
  menuDaFuncao,
  mesclarPrevia,
  previaDaFuncao,
} from '../fraseDaFuncao';
import { DONO_DAS_CHAVES } from '../areasDaFuncao';

// #2308, especificação 7.7 e 8: a fonte única do que a função pode. O "Ligar as duas" mora no PerguntaCuidado (e no
// spec dele); aqui vale o que ele grava: campaign_manage e campaign_send (rodada 4).
const comAsDuas = permissions => [
  ...permissions,
  'campaign_manage',
  'campaign_send',
];

describe('fraseDaFuncao', () => {
  it('Atendente: próprias e novas, cria e move as vendas, só olha os contatos', () => {
    expect(fraseDaFuncao(PRESETS.AGENT())).toEqual({
      destaque: 'PROPRIAS_E_NOVAS',
      resto: ['VENDAS_MEXE', 'CONTATOS_SO_OLHA'],
    });
  });

  it('Marketing: não atende, só olha as vendas, dispara campanhas, cria e muda os contatos', () => {
    expect(fraseDaFuncao(PRESETS.MARKETING())).toEqual({
      destaque: 'NAO_ATENDE',
      resto: ['VENDAS_SO_OLHA', 'CAMPANHAS_DISPARA', 'CONTATOS_MEXE'],
    });
  });

  // Rodada 4: a função antiga "Só olha" com mover as vendas move de verdade (CardPolicy#move?); a frase diz isso,
  // como o Pode ("Mover as vendas entre as colunas").
  it('só olha e move as vendas: "Olha e move as vendas."', () => {
    const { resto } = fraseDaFuncao(['crm_view', 'crm_move_cards']);
    expect(resto).toEqual(['VENDAS_OLHA_E_MOVE']);
    expect(ptBR.FUNCOES_EQUIPE.FRASE[resto[0]]).toBe('Olha e move as vendas.');
  });

  // Rodada 5: toda chave que a frase pode devolver existe nos dois idiomas. As funções abaixo passam por todos os
  // ramos (cada nível de conversas, vendas, campanhas e contatos); a lista do fim confere que nenhum ficou de fora.
  it('toda chave da frase existe em pt_BR e en', () => {
    const funcoes = [
      ...Object.values(PRESETS).map(preset => preset()),
      [],
      ['conversation_view'],
      ['conversation_view', 'conversation_message_delete'],
      ['conversation_participating_manage'],
      ['conversation_manage', 'crm_admin'],
      ['crm_view', 'crm_move_cards'],
      ['campaign_manage'],
      ['contact_view'],
      ['contact_view', 'contact_export'],
      ['crm_view', 'crm_export'],
      ['contact_manage'],
    ];
    const chaves = [
      ...new Set(
        funcoes.flatMap(permissions => {
          const { destaque, resto } = fraseDaFuncao(permissions);
          return [destaque, ...resto];
        })
      ),
    ].sort();
    expect(chaves).toEqual(Object.keys(ptBR.FUNCOES_EQUIPE.FRASE).sort());
    [ptBR, en].forEach(idioma => {
      chaves.forEach(chave => {
        expect(idioma.FUNCOES_EQUIPE.FRASE[chave], chave).toBeTruthy();
      });
    });
  });

  it('área sem acesso não entra; crm_admin cuida de tudo nas vendas', () => {
    expect(fraseDaFuncao(['conversation_manage', 'crm_admin'])).toEqual({
      destaque: 'TODAS',
      resto: ['VENDAS_TUDO'],
    });
  });
});

describe('prévia "Como vai ficar"', () => {
  it('Atendente: Pode, Não pode e menu da especificação 8', () => {
    expect(previaDaFuncao(PRESETS.AGENT())).toMatchObject({
      pode: [
        'RESPONDER_ENTREGUES',
        'PEGAR_NOVAS',
        'AJUDAR_PELO_LINK',
        'CRIAR_MOVER_VENDAS',
      ],
      naoPode: ['LER_COLEGAS', 'MUDAR_CONTATOS', 'EXPORTAR_CONTATOS'],
      menu: ['CONVERSAS', 'CONTATOS', 'VENDAS'],
    });
  });

  it('sem sales_value_view, metas não aparece no Pode (decisão 14A)', () => {
    const tudo = toggleExtra(moduleByKey('CRM'), 'crm_admin', PRESETS.AGENT());
    expect(tudo).toContain('crm_metas_manage');
    expect(previaDaFuncao(tudo).pode).not.toContain('METAS_DO_MES');
    expect(previaDaFuncao([...tudo, 'sales_value_view']).pode).toContain(
      'METAS_DO_MES'
    );
  });

  it('estável: o novo entra no fim do Pode com "novo"; o Não pode não muda', () => {
    const antes = PRESETS.AGENT();
    const previa = mesclarPrevia(
      previaDaFuncao(antes),
      previaDaFuncao(comAsDuas(antes))
    );
    expect(previa.pode.slice(-2)).toEqual([
      { id: 'CAMPAIGN_MANAGE', novo: true },
      { id: 'CAMPAIGN_SEND', novo: true },
    ]);
    expect(previa.pode.filter(item => item.novo)).toHaveLength(2);
    expect(previa.naoPode).toEqual(previaDaFuncao(antes).naoPode);
    expect(previa.menu).toContain('CAMPANHAS');
  });

  it('um item do Pode que sai vai para o Não pode, sem marca, se for das que valem lá', () => {
    const sdr = PRESETS.SDR();
    const soOlhaContatos = setLevel(moduleByKey('CONTACTS'), 'view', sdr);
    const previa = mesclarPrevia(
      previaDaFuncao(sdr),
      previaDaFuncao(soOlhaContatos)
    );
    expect(previa.pode.map(item => item.id)).not.toContain('MUDAR_CONTATOS');
    expect(previa.naoPode).toContain('MUDAR_CONTATOS');
  });
});

describe('selo de cuidado', () => {
  it('Vendedor pronto não tem selo', () => {
    expect(cuidadosDaFuncao(PRESETS.SDR())).toEqual([]);
  });

  it('com crm_admin, as seis que ele inclui ficam dentro dele; disparar vem antes da planilha', () => {
    expect(
      cuidadosDaFuncao([
        'crm_admin',
        'crm_export',
        'crm_metas_manage',
        'contact_export',
        'campaign_send',
      ])
    ).toEqual(['crm_admin', 'campaign_send', 'contact_export']);
  });

  // Rodada 3: função antiga "Só olha" com mover as vendas (gravada pela tela de antes). O servidor deixa mover.
  it('"Só olha" + crm_move_cards: a prévia diz que move as vendas, e não "Não pode criar e mover"', () => {
    const previa = previaDaFuncao(['crm_view', 'crm_move_cards']);
    expect(previa.pode).toContain('MOVER_VENDAS');
    expect(previa.naoPode).not.toContain('CRIAR_MOVER_VENDAS');
    expect(previaDaFuncao(['crm_view']).naoPode).toContain(
      'CRIAR_MOVER_VENDAS'
    );
  });

  // Rodada 3: crm_admin sem as seis gravadas lê como o servidor (CrmPermissions#crm_permission?), a mesma leitura
  // da Perda de acesso; metas sem R$ continuam fora.
  it('crm_admin sem as seis gravadas: a prévia mostra o que o servidor dá, sem metas sem R$', () => {
    const { pode } = previaDaFuncao(['crm_view', 'crm_admin']);
    expect(pode).toEqual(
      expect.arrayContaining([
        'CRIAR_MOVER_VENDAS',
        'ARQUIVAR_VENDAS',
        'MONTAR_COLUNAS',
        'RELATORIOS_DAS_VENDAS',
        'EXPORTAR_VENDAS',
        'IA_NAS_VENDAS',
      ])
    );
    expect(pode).not.toContain('METAS_DO_MES');
  });
});

// Rodada 5: o que cada capacidade cobre mora nela (`cobre`). Toda capacidade coberta é uma do Pode, com texto.
describe('contidasEm', () => {
  it('a maior cobre as menores', () => {
    expect(contidasEm(['LER_E_ATENDER_TODAS'])).toEqual([
      'RESPONDER_ENTREGUES',
      'PEGAR_NOVAS',
      'AJUDAR_PELO_LINK',
      'LER_COLEGAS',
    ]);
    expect(contidasEm(['CRIAR_MOVER_VENDAS', 'FINANCIAL_MANAGE'])).toEqual([
      'MOVER_VENDAS',
      'FINANCIAL_VIEW',
    ]);
    expect(contidasEm(['APAGAR_MENSAGENS'])).toEqual([]);
  });

  it('toda capacidade coberta existe no Pode, em pt_BR e en', () => {
    const cobertas = contidasEm(Object.keys(ptBR.FUNCOES_EQUIPE.PODE));
    expect(cobertas).toContain('FINANCIAL_VIEW');
    [ptBR, en].forEach(idioma => {
      cobertas.forEach(id => {
        expect(idioma.FUNCOES_EQUIPE.PODE[id], id).toBeTruthy();
      });
    });
  });
});

// Revisão do #2308 (rodada final): o "O menu vai mostrar" segue o menu lateral (Sidebar.vue). Seus posts é item de
// primeiro nível e Agendamento mora no grupo das vendas: nenhum dos dois cai em Configurações.
describe('menuDaFuncao', () => {
  it('Seus posts aparece com o próprio nome, não em Configurações', () => {
    expect(menuDaFuncao(['posts_view'])).toEqual(['SEUS_POSTS']);
  });

  it('Agendamento aparece dentro de Vendas', () => {
    expect(menuDaFuncao(['agendamento_view'])).toEqual(['VENDAS']);
  });

  it('o que mora em Configurações continua lá', () => {
    expect(menuDaFuncao(['label_manage'])).toEqual(['CONFIGURACOES']);
  });

  it('todo item do menu tem nome em pt_BR e en', () => {
    const todas = Object.values(DONO_DAS_CHAVES).flat();
    const itens = menuDaFuncao(todas);
    expect(itens).toContain('SEUS_POSTS');
    [ptBR, en].forEach(idioma => {
      itens.forEach(item => {
        expect(idioma.FUNCOES_EQUIPE.MENU[item], item).toBeTruthy();
      });
    });
  });
});
