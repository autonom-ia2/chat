import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
import { PRESETS } from '../../customRoles/permissionMatrix';
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

// Um contrato como o que o PR do contrato vai gerar: as capacidades de vendas que o "Sem função" não tem, um id que
// a tela ainda não conhece e um extra com chave.
const capacidade = (id, chaves, pode = false) => ({
  id,
  chaves,
  premissas: [],
  pode,
});
const FIXTURE = {
  capacidades: [
    ...contrato.capacidades,
    capacidade('valores_das_vendas', ['sales_value_view']),
    capacidade('montar_colunas', ['crm_manage_pipelines']),
    capacidade('ia_das_vendas', ['crm_manage_ai']),
    capacidade('cuidar_de_tudo_nas_vendas', ['crm_admin']),
    capacidade('metas_do_mes', ['crm_metas_manage']),
    capacidade('coisa_que_a_tela_nao_conhece', ['label_manage']),
  ],
  extras: [
    capacidade('anuncio_de_origem', ['meta_ads_view'], true),
    capacidade('responsavel_de_agendamento', []),
  ],
};
const COM_R$ = {
  ...FIXTURE,
  capacidades: FIXTURE.capacidades.map(item =>
    item.id === 'valores_das_vendas' ? { ...item, pode: true } : item
  ),
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
      ],
      perde: ['procurar_clientes_novos'],
    });
    expect(diff(PRESETS.SUPERVISOR(), ligada).perde[0]).toBe(
      'relatorios_das_vendas'
    );
  });

  it('as áreas inteiras que o "Sem função" não dá também saem: Supervisor e Operação não perdem "nada"', () => {
    expect(diff(PRESETS.SUPERVISOR()).perde).toEqual([
      'KNOWLEDGE_BASE:VER',
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

  it('"Cuida de tudo" no contrato de hoje: crm_admin vale como dona das chaves das vendas', () => {
    const tudo = escolherNivelDeVendas('tudo', PRESETS.AGENT());
    expect(diff(tudo)).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'contatos',
        'respostas_prontas',
        'apagar_mensagens',
      ],
      perde: ['planilha_de_clientes', 'KNOWLEDGE_BASE:VER', 'CRM:PARTE'],
    });
  });

  it('só crm_admin, com o contrato novo: cada pedaço das vendas sai pelo nome, sem "Mexer em Vendas"', () => {
    expect(diff(['crm_admin'], desligada, FIXTURE)).toEqual({
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

  it('Gerente de vendas perde os valores em R$ e as metas; o vendedor sem R$ não ganha nem perde R$', () => {
    expect(diff(PRESETS.SALES_MANAGER(), desligada, FIXTURE).perde).toEqual([
      'procurar_clientes_novos',
      'planilha_de_clientes',
      'valores_das_vendas',
      'montar_colunas',
      'metas_do_mes',
      'REPORTS:VER',
      'AUTONOMIA:VER',
      'CAMPAIGNS:VER',
    ]);
    const vendedor = diff(PRESETS.AGENT(), desligada, FIXTURE);
    expect([...vendedor.ganha, ...vendedor.perde]).not.toContain(
      'valores_das_vendas'
    );
  });

  it('se o "Sem função" passar a ver R$, o ganho vem marcado como delegação (a tela mostra, não trava)', () => {
    const { ganha } = diffEntre(PRESETS.AGENT(), desligada, COM_R$);
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

  it('as capacidades seguem o contrato, na ordem dele, com a flag resolvida', () => {
    const ids = contrato.capacidades.map(item => item.id);
    expect(capacidadesSemFuncao(desligada).map(item => item.id)).toEqual(ids);
    const relatorios = flag =>
      capacidadesSemFuncao(flag).find(
        item => item.id === 'relatorios_das_vendas'
      );
    expect(relatorios(desligada).pode).toBe(true);
    expect(relatorios(ligada).pode).toBe(false);
  });

  it('cada capacidade do contrato e as cinco novas de vendas têm texto em en e pt_BR', () => {
    const ids = [
      ...contrato.capacidades.map(item => item.id),
      'valores_das_vendas',
      'montar_colunas',
      'ia_das_vendas',
      'cuidar_de_tudo_nas_vendas',
      'metas_do_mes',
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
