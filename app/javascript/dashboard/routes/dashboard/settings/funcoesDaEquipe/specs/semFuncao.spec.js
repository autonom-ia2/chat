import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
import {
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { escolherNivelDeVendas } from '../nivelDeVendas';
import { capacidadesSemFuncao, diffEntre } from '../semFuncao';
import contrato from '../semFuncaoCapacidades.json';

// #2308, especificação 5.E, 7.9 e 14: o diff "Vão passar a poder / Vão deixar de" sai do contrato gerado das
// policies, nunca de uma lista por função; os relatórios das vendas seguem a flag crm_numeros_lentes da conta.
const LENTES = 'crm_numeros_lentes';
const desligada = () => false;
const ligada = flag => flag === LENTES;

// O que a tela mostra de cada item: o id da capacidade, ou a área com o tamanho da perda.
const nomes = itens =>
  itens.map(item =>
    item.tipo === 'area' ? `${item.chave}:${item.jeito}` : item.chave
  );
const diff = (permissions, flag = desligada, outro = contrato) => {
  const { ganha, perde } = diffEntre(permissions, flag, outro);
  return { ganha: nomes(ganha), perde: nomes(perde) };
};

// O contrato gerado com um id que a tela ainda não conhece.
const FIXTURE = {
  ...contrato,
  capacidades: [
    ...contrato.capacidades,
    {
      id: 'coisa_que_a_tela_nao_conhece',
      chaves: ['label_manage'],
      premissas: [],
      pode: false,
    },
  ],
};

describe('semFuncao', () => {
  it('com crm_numeros_lentes desligada, quem fica sem função passa a ver os relatórios das vendas', () => {
    expect(diff(PRESETS.SDR())).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'respostas_prontas',
        'apagar_mensagens',
        'arquivar_vendas',
        'relatorios_das_vendas',
        'valores_das_vendas',
        'anuncio_de_origem',
      ],
      perde: ['procurar_clientes_novos'],
    });
  });

  it('com crm_numeros_lentes ligada, não ganha os relatórios, e quem tinha perde', () => {
    expect(diff(PRESETS.SDR(), ligada)).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'respostas_prontas',
        'apagar_mensagens',
        'arquivar_vendas',
        'valores_das_vendas',
        'anuncio_de_origem',
      ],
      perde: ['procurar_clientes_novos'],
    });
    expect(diff(PRESETS.SUPERVISOR(), ligada).perde[0]).toBe(
      'relatorios_das_vendas'
    );
  });

  it('as áreas inteiras que o "Sem função" não dá também saem: Supervisor e Operação não perdem "nada"', () => {
    expect(diff(PRESETS.SUPERVISOR()).perde).toEqual([
      'REPORTS:VER',
      'AUTONOMIA:VER',
      'INBOXES:VER',
      'AUTOMATIONS:VER',
      'LABELS:MEXER',
      'MACROS:MEXER',
    ]);
    expect(diff(PRESETS.OPERATIONS()).perde).toEqual([
      'AUTONOMIA:MEXER',
      'INBOXES:MEXER',
      'AUTOMATIONS:MEXER',
      'LABELS:MEXER',
      'ATTRIBUTES:MEXER',
      'MACROS:MEXER',
      'SLA:MEXER',
    ]);
  });

  // Rodada 4: o extra anuncio_de_origem (meta_ads_view) diz só o que o sem função ganha; a página de Anúncios ele
  // não tem (sem_funcao_capacidades.rb), e quem a via perde.
  it('quem vê a página de Anúncios perde a página; o extra não a esconde', () => {
    const comAnuncios = setLevel(
      moduleByKey('META_ADS'),
      'view',
      PRESETS.SDR()
    );
    const { ganha, perde } = diff(comAnuncios);
    expect(perde).toContain('META_ADS:VER');
    expect(ganha).not.toContain('anuncio_de_origem');
    expect(diff(PRESETS.SDR()).ganha).toContain('anuncio_de_origem');
  });

  it('quem só olha os contatos ganha mudar os contatos; quem leva planilha perde', () => {
    expect(diff(PRESETS.AGENT()).ganha).toContain('contatos');
    expect(diff(PRESETS.MARKETING()).perde).toContain('planilha_de_clientes');
  });

  it('a chave implicada conta dos dois lados: crm_manage_cards traz crm_view', () => {
    expect(diff(['crm_manage_cards', 'crm_move_cards']).ganha).not.toContain(
      'vendas_das_colunas'
    );
    // Quem só olha as vendas não perde "Ver Vendas": o "Sem função" mexe nas vendas, e mexer traz ver.
    expect(diff(['crm_view']).perde).toEqual([]);
    // Atender todas as conversas cobre os dois alcances, que setLevel grava junto.
    expect(
      diff([
        'conversation_participating_manage',
        'conversation_unassigned_manage',
      ]).perde
    ).toEqual([]);
  });

  it('a implicada também conta do lado da função: crm_export traz crm_view, e a perda de ver as vendas aparece', () => {
    const soVer = {
      ...contrato,
      capacidades: [
        {
          id: 'ver_as_vendas',
          chaves: ['crm_view'],
          premissas: [],
          pode: false,
        },
      ],
      extras: [],
    };
    expect(diff(['crm_export'], desligada, soVer).perde).toContain(
      'ver_as_vendas'
    );
  });

  it('"Cuida de tudo" sem R$: cada pedaço das vendas sai pelo nome, sem "Usar uma parte de Vendas", e ganha R$', () => {
    const tudo = escolherNivelDeVendas('tudo', PRESETS.AGENT());
    expect(diff(tudo)).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'contatos',
        'respostas_prontas',
        'apagar_mensagens',
        'valores_das_vendas',
        'anuncio_de_origem',
      ],
      perde: [
        'planilha_de_clientes',
        'montar_colunas',
        'ia_das_vendas',
        'cuidar_de_tudo_nas_vendas',
      ],
    });
  });

  it('"Cuida de tudo" com R$ não ganha R$ e perde as metas do mês', () => {
    const tudo = [
      ...escolherNivelDeVendas('tudo', PRESETS.AGENT()),
      'sales_value_view',
    ];
    expect(diff(tudo)).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'contatos',
        'respostas_prontas',
        'apagar_mensagens',
        'anuncio_de_origem',
      ],
      perde: [
        'planilha_de_clientes',
        'montar_colunas',
        'ia_das_vendas',
        'cuidar_de_tudo_nas_vendas',
        'metas_do_mes',
      ],
    });
  });

  it('metas sem R$ não valem no servidor: quem fica sem função não as perde', () => {
    expect(diff(['crm_metas_manage']).perde).toEqual([]);
    expect(diff(['crm_admin']).perde).toEqual([
      'planilha_de_clientes',
      'montar_colunas',
      'ia_das_vendas',
      'cuidar_de_tudo_nas_vendas',
    ]);
  });

  it('Gerente de vendas tem R$ e não o perde, mas perde as metas; o vendedor sem R$ ganha R$', () => {
    const gerente = diff(PRESETS.SALES_MANAGER());
    expect(gerente.perde).toEqual([
      'procurar_clientes_novos',
      'planilha_de_clientes',
      'montar_colunas',
      'metas_do_mes',
      'REPORTS:VER',
      'AUTONOMIA:VER',
      'CAMPAIGNS:VER',
    ]);
    expect(gerente.ganha).not.toContain('valores_das_vendas');
    const vendedor = diff(PRESETS.AGENT());
    expect(vendedor.ganha).toContain('valores_das_vendas');
    expect(vendedor.perde).not.toContain('valores_das_vendas');
  });

  it('quem já vê o anúncio de origem (meta_ads_view, ou meta_ads_manage que o implica) não o ganha', () => {
    expect(diff(['meta_ads_view']).ganha).not.toContain('anuncio_de_origem');
    expect(diff(['meta_ads_manage']).ganha).not.toContain('anuncio_de_origem');
    expect(diff([]).ganha).toContain('anuncio_de_origem');
  });

  it('o ganho de R$ vem marcado como delegação (a tela mostra, não trava)', () => {
    const { ganha } = diffEntre(PRESETS.AGENT(), desligada);
    const valores = ganha.find(item => item.chave === 'valores_das_vendas');
    expect(valores).toEqual({
      chave: 'valores_das_vendas',
      tipo: 'capacidade',
      chaves: ['sales_value_view'],
      delegacao: true,
    });
  });

  it('o id que a tela não conhece entra no diff com as chaves, para a frase genérica da área', () => {
    const { perde } = diffEntre(['label_manage'], desligada, FIXTURE);
    expect(perde).toEqual([
      {
        chave: 'coisa_que_a_tela_nao_conhece',
        tipo: 'capacidade',
        chaves: ['label_manage'],
        delegacao: false,
      },
    ]);
  });

  it('as capacidades seguem o contrato, na ordem dele, com o extra que tem chave e a flag resolvida', () => {
    expect(capacidadesSemFuncao(desligada).map(item => item.id)).toEqual([
      'conversas_dos_colegas',
      'contatos',
      'respostas_prontas',
      'apagar_mensagens',
      'vendas_das_colunas',
      'arquivar_vendas',
      'relatorios_das_vendas',
      'procurar_clientes_novos',
      'planilha_de_clientes',
      'valores_das_vendas',
      'montar_colunas',
      'ia_das_vendas',
      'cuidar_de_tudo_nas_vendas',
      'metas_do_mes',
      'anuncio_de_origem',
    ]);
    const relatorios = flag =>
      capacidadesSemFuncao(flag).find(
        item => item.id === 'relatorios_das_vendas'
      );
    expect(relatorios(desligada).pode).toBe(true);
    expect(relatorios(ligada).pode).toBe(false);
  });

  it('cada capacidade do contrato e o extra com chave têm texto em en e pt_BR', () => {
    const ids = [
      ...contrato.capacidades.map(item => item.id),
      'anuncio_de_origem',
    ];
    ids.forEach(id => {
      [ptBR, en].forEach(catalogo => {
        expect(catalogo.FUNCOES_EQUIPE.SEM_FUNCAO[id].LISTA).toBeTruthy();
        expect(catalogo.FUNCOES_EQUIPE.SEM_FUNCAO[id].CURTO).toBeTruthy();
      });
    });
  });
});
