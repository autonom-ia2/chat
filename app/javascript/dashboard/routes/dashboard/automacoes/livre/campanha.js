// #2414 G14 (#2630) — o passo "campanha": mandar uma campanha de WhatsApp para
// quem tem as etiquetas, ou marcar o contato como "não recebe". A régua é a do
// servidor (Autonomia::Automacao::PassoDeCampanha): caixa do WhatsApp oficial
// na Cloud API, modelo aprovado de utilidade ou de propaganda, com o corpo
// pedindo {{1}}..{{n}} e nada além do corpo para preencher.
import {
  corpoDoModelo,
  numeradas,
  pedeMais,
  variaveisDoCorpo,
} from './modeloWhatsapp';

// Utilidade e propaganda (decisão do Rodrigo, 06/11), a mesma constante do
// servidor. O modelo de propaganda mostra o aviso de custo (ehPropaganda).
export const CATEGORIAS_DA_CAMPANHA = ['UTILITY', 'MARKETING'];
const CANAL = 'Channel::Whatsapp';
const PROVEDOR = 'whatsapp_cloud';

export const caixasDaCampanha = caixas =>
  (caixas || []).filter(
    caixa => caixa.channel_type === CANAL && caixa.provider === PROVEDOR
  );

export const serveNaCampanha = modelo =>
  String(modelo.status).toLowerCase() === 'approved' &&
  CATEGORIAS_DA_CAMPANHA.includes(String(modelo.category).toUpperCase()) &&
  numeradas(variaveisDoCorpo(corpoDoModelo(modelo))) &&
  !(modelo.components || []).some(pedeMais);

export const modelosDaCaixa = caixa =>
  (caixa?.message_templates || []).filter(serveNaCampanha);

export const ehPropaganda = modelo =>
  String(modelo?.category).toUpperCase() === 'MARKETING';

// Só o que cada escolha precisa: o "não receber" não leva os campos do disparo.
export const comFaz = (passo, faz) =>
  faz === 'disparar'
    ? { ...passo, faz, etiquetas: passo.etiquetas || [] }
    : { id: passo.id, tipo: passo.tipo, faz };

const escrito = texto => typeof texto === 'string' && texto.trim() !== '';

export const campanhaPronta = passo => {
  if (passo?.faz === 'nao_receber') return true;
  if (passo?.faz !== 'disparar') return false;
  return (
    escrito(passo.titulo) &&
    Number.isInteger(passo.caixa_id) &&
    Boolean(passo.modelo?.nome) &&
    (passo.modelo.variaveis || []).every(partes =>
      (partes || []).some(escrito)
    ) &&
    (passo.etiquetas || []).length > 0
  );
};

const C = 'AUTOMACAO_LIVRE.CAMPANHA';

// A frase da linha do passo.
export const fraseDaCampanha = (passo, t) =>
  passo.faz === 'disparar'
    ? t(`${C}.FRASE_DISPARAR`, { titulo: passo.titulo || '' })
    : t(`${C}.FRASE_NAO_RECEBER`);
