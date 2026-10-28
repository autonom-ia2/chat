import {
  CONVERSATION_LEVELS,
  LEVELS,
  MODULES,
  PRESETS,
  getLevel,
  moduleByKey,
} from '../customRoles/permissionMatrix';
import { LOCK_REASONS } from 'dashboard/helper/peopleAccess';
import { TUDO, nivelDeVendas } from './nivelDeVendas';
import { cuidadosDaFuncao } from './fraseDaFuncao';
import { motivoDaTrava } from './motivoDaTrava';

// Os cartões de função pronta da Escolha e do vazio (#2308, especificação 5.B1 e 7.6). Cada um mostra até 3
// capacidades curtas (FUNCOES_EQUIPE.CURTO) do corte: o preset sem as chaves que quem monta não pode dar.
export const PRONTAS = [
  {
    chave: 'AGENT',
    icone: 'i-lucide-headset',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    chave: 'SDR',
    icone: 'i-lucide-handshake',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    chave: 'SUPERVISOR',
    icone: 'i-lucide-eye',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    chave: 'SALES_MANAGER',
    icone: 'i-lucide-chart-no-axes-combined',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  {
    chave: 'MARKETING',
    icone: 'i-lucide-megaphone',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  {
    chave: 'OPERATIONS',
    icone: 'i-lucide-wrench',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    chave: 'READ_ONLY',
    icone: 'i-lucide-book-open',
    tom: 'bg-n-alpha-2 text-n-slate-11',
  },
  // Sem ver os custos, não há Financeiro: o cartão sai e fica só o cadeado.
  {
    chave: 'FINANCE',
    icone: 'i-lucide-wallet',
    tom: 'bg-n-teal-3 text-n-teal-11',
    essenciais: ['financial_view'],
  },
];
export const DESTAQUES = ['AGENT', 'SDR', 'SUPERVISOR'];

const nivel = (area, permissions) => getLevel(moduleByKey(area), permissions);
const curto = (chave, tipo = 'pode') => ({ chave, tipo });
const mexe = (area, permissions) => nivel(area, permissions) === LEVELS.MANAGE;
const mexeNasVendas = permissions =>
  [LEVELS.MANAGE, TUDO].includes(nivelDeVendas(permissions));

const CONVERSA_CURTA = {
  [CONVERSATION_LEVELS.ALL]: curto('TODAS'),
  [CONVERSATION_LEVELS.LIMITED]: curto('PROPRIAS'),
  [CONVERSATION_LEVELS.VIEW]: curto('SO_OLHA_CONVERSAS', 'soOlha'),
};

const campanhas = p => {
  if (!p.includes('campaign_manage')) return null;
  return curto(p.includes('campaign_send') ? 'CAMPANHAS_DISPARA' : 'CAMPANHAS');
};
const vendas = p => {
  if (!mexeNasVendas(p)) return null;
  if (p.includes('crm_manage_pipelines')) return curto('VENDAS_E_COLUNAS');
  return curto(mexe('CONTACTS', p) ? 'CONTATOS_E_VENDAS' : 'VENDAS');
};
const arruma = p =>
  ['inbox_manage', 'autonomia_manage', 'automation_manage'].every(chave =>
    p.includes(chave)
  )
    ? curto('ARRUMA')
    : null;
// Quem mexe nas vendas já falou dos contatos nelas (ou trocou pelas colunas, mais próprias da função).
const contatos = p => {
  if (mexe('CONTACTS', p)) return mexeNasVendas(p) ? null : curto('CONTATOS');
  return nivel('CONTACTS', p) === LEVELS.VIEW
    ? curto('SO_OLHA_CONTATOS', 'soOlha')
    : null;
};
const relatorios = p =>
  p.includes('report_manage') || p.includes('crm_view_reports')
    ? curto('RELATORIOS')
    : null;
const procura = p =>
  p.includes('prospecting_manage') ? curto('PROCURA') : null;

const AREAS_QUE_SO_OLHA = ['CONTACTS', 'CRM', 'CAMPAIGNS', 'REPORTS'];
const soOlha = p =>
  !MODULES.some(module => mexe(module.key, p)) &&
  !mexeNasVendas(p) &&
  ![CONVERSATION_LEVELS.LIMITED, CONVERSATION_LEVELS.ALL].includes(
    nivel('CONVERSATIONS', p)
  );

const positivas = p => {
  if (soOlha(p)) {
    const areas = AREAS_QUE_SO_OLHA.filter(
      area => nivel(area, p) !== LEVELS.NONE
    );
    return areas.length ? [{ ...curto('SO_OLHA_AREAS', 'soOlha'), areas }] : [];
  }
  return [
    CONVERSA_CURTA[nivel('CONVERSATIONS', p)],
    campanhas(p),
    vendas(p),
    arruma(p),
    contatos(p),
    relatorios(p),
    procura(p),
  ].filter(Boolean);
};

// Até 3, com tipo (pode | soOlha | naoFaz) para o ícone. "Não atende conversas" sempre entra, por último.
export const podeCurto = permissions => {
  const naoAtende =
    nivel('CONVERSATIONS', permissions) === CONVERSATION_LEVELS.NONE
      ? [curto('NAO_ATENDE', 'naoFaz')]
      : [];
  return [
    ...positivas(permissions).slice(0, 3 - naoAtende.length),
    ...naoAtende,
  ];
};

// A ordem em que as travas do cartão citam as chaves; as outras vêm depois, na ordem do preset.
const ORDEM_DAS_TRAVAS = [
  'crm_export',
  'crm_metas_manage',
  'sales_value_view',
  'insurance_view',
  'insurance_manage',
];
const posicao = chave =>
  ORDEM_DAS_TRAVAS.includes(chave)
    ? ORDEM_DAS_TRAVAS.indexOf(chave)
    : ORDEM_DAS_TRAVAS.length;

const agrupar = (preset, motivos) =>
  [LOCK_REASONS.MISSING, LOCK_REASONS.DELEGATION]
    .map(motivo => ({
      motivo,
      chaves: preset
        .filter(chave => motivos.get(chave) === motivo)
        .sort((a, b) => posicao(a) - posicao(b)),
    }))
    .filter(trava => trava.chaves.length);

export const cartaoPronto = (pronta, giver) => {
  const preset = PRESETS[pronta.chave]();
  const motivos = new Map(
    preset.map(chave => [chave, motivoDaTrava(giver, chave)])
  );
  const corte = preset.filter(chave => !motivos.get(chave));
  return {
    ...pronta,
    corte,
    capacidades: podeCurto(corte),
    selo: cuidadosDaFuncao(corte),
    travas: agrupar(preset, motivos),
    fora: (pronta.essenciais || []).some(chave => motivos.get(chave)),
  };
};

export const cartoesProntos = giver =>
  PRONTAS.map(pronta => cartaoPronto(pronta, giver));
