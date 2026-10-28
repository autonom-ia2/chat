import {
  CONVERSATION_LEVELS,
  LEVELS,
  MODULES,
} from '../customRoles/permissionMatrix';
import { nivel } from './fraseDaFuncao';
import { mexeNasVendas } from './nivelDeVendas';

// As capacidades curtas dos cartões prontos (#2308, especificação 7.6): até 3, com tipo (pode | soOlha | naoFaz)
// para o ícone. Chaves de FUNCOES_EQUIPE.CURTO; quem mostra traduz.
const curto = (chave, tipo = 'pode') => ({ chave, tipo });
const mexe = (area, permissions) => nivel(area, permissions) === LEVELS.MANAGE;

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
