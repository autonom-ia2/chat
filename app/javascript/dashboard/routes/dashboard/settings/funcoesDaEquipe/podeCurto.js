import {
  CONVERSATION_LEVELS,
  LEVELS,
  MODULES,
} from '../customRoles/permissionMatrix';
import { nivel, soOlhaNaArea } from './fraseDaFuncao';
import { mexeNasVendas } from './nivelDeVendas';

// As capacidades curtas dos cartões prontos (#2308, especificação 7.6): até 3, com tipo (pode | soOlha | ve | naoFaz)
// para o ícone. Chaves de FUNCOES_EQUIPE.CURTO; quem mostra traduz. Uma área no nível de ver "só olha" só quando nada
// muda nela (soOlhaNaArea, a mesma regra da frase e da Perda de acesso); senão "vê", sem o "só".
const curto = (chave, tipo = 'pode') => ({ chave, tipo });
const mexe = (area, permissions) => nivel(area, permissions) === LEVELS.MANAGE;

const deVer = (area, permissions, chaveSoOlha, chaveVe) =>
  soOlhaNaArea(area, permissions)
    ? curto(chaveSoOlha, 'soOlha')
    : curto(chaveVe, 've');

const CONVERSA_CURTA = {
  [CONVERSATION_LEVELS.ALL]: () => curto('TODAS'),
  [CONVERSATION_LEVELS.LIMITED]: () => curto('PROPRIAS'),
  [CONVERSATION_LEVELS.VIEW]: p =>
    deVer('CONVERSATIONS', p, 'SO_OLHA_CONVERSAS', 'VE_CONVERSAS'),
};
const conversas = p => CONVERSA_CURTA[nivel('CONVERSATIONS', p)]?.(p) || null;

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
    ? deVer('CONTACTS', p, 'SO_OLHA_CONTATOS', 'VE_CONTATOS')
    : null;
};
const relatorios = p =>
  p.includes('report_manage') || p.includes('crm_view_reports')
    ? curto('RELATORIOS')
    : null;
const procura = p =>
  p.includes('prospecting_manage') ? curto('PROCURA') : null;

const AREAS_QUE_OLHA = ['CONTACTS', 'CRM', 'CAMPAIGNS', 'REPORTS'];
// A função que não mexe em nada pelo nível: o cartão diz as áreas que olha.
const semMexer = p =>
  !MODULES.some(module => mexe(module.key, p)) &&
  !mexeNasVendas(p) &&
  ![CONVERSATION_LEVELS.LIMITED, CONVERSATION_LEVELS.ALL].includes(
    nivel('CONVERSATIONS', p)
  );

const positivas = p => {
  if (semMexer(p)) {
    const areas = AREAS_QUE_OLHA.filter(area => nivel(area, p) !== LEVELS.NONE);
    const soOlhando = areas.filter(area => soOlhaNaArea(area, p));
    const vendo = areas.filter(area => !soOlhando.includes(area));
    return [
      soOlhando.length && {
        ...curto('SO_OLHA_AREAS', 'soOlha'),
        areas: soOlhando,
      },
      vendo.length && { ...curto('VE_AREAS', 've'), areas: vendo },
    ].filter(Boolean);
  }
  return [
    conversas(p),
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
