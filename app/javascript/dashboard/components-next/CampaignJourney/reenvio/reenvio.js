// #3101 — "Mandar de novo" da revisão da campanha: uma segunda mensagem, X dias depois, para quem não respondeu (ou não
// leu). O valor fica no rascunho da jornada (draft.reenvio); null = não manda de novo.
//
// A segunda mensagem depende do canal: no WhatsApp Oficial é outro modelo aprovado (fora das 24 horas a Meta só deixa
// mandar modelo); no SMS e no WhatsApp API é um texto; no e-mail muda só o assunto (o conteúdo é o do primeiro e-mail).
import { CAMPAIGN_CHANNELS } from '../campaignChannels';
import { allBound } from '../templateVariables';

export const DIAS_DO_REENVIO = [1, 2, 3, 5, 7];
export const DIAS_PADRAO = 3;
// O teto do texto da segunda mensagem no SMS e no WhatsApp API (o mesmo do servidor, CampaignJourney::Reenvio).
export const MAXIMO_DO_TEXTO = 1000;

export const QUEM = { NAO_RESPONDEU: 'nao_respondeu', NAO_LEU: 'nao_leu' };

export const MENSAGEM = {
  MODELO: 'modelo',
  TEXTO: 'texto',
  ASSUNTO: 'assunto',
};

const MENSAGEM_DO_CANAL = {
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: MENSAGEM.MODELO,
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: MENSAGEM.TEXTO,
  [CAMPAIGN_CHANNELS.SMS]: MENSAGEM.TEXTO,
  [CAMPAIGN_CHANNELS.EMAIL]: MENSAGEM.ASSUNTO,
};

// "Não leu" só onde o canal avisa a leitura de verdade: o WhatsApp Oficial (campaign_recipients.read_at). O SMS não
// avisa; a abertura do e-mail engana (o celular abre sozinho para proteger a privacidade).
const CANAIS_QUE_AVISAM_LEITURA = [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL];

/** O tipo da segunda mensagem do canal, ou null quando o canal não tem reenvio (chat ao vivo). */
export const mensagemDoCanal = canal => MENSAGEM_DO_CANAL[canal] || null;

/** Para quem dá para mandar de novo neste canal, na ordem da tela. */
export const quemPodeEscolher = canal =>
  CANAIS_QUE_AVISAM_LEITURA.includes(canal)
    ? [QUEM.NAO_RESPONDEU, QUEM.NAO_LEU]
    : [QUEM.NAO_RESPONDEU];

/** O reenvio recém-ligado: quem não respondeu, 3 dias depois. A tela já põe o texto ou o assunto de exemplo. */
export const reenvioNovo = ({ texto = '', assunto = '' } = {}) => ({
  quem: QUEM.NAO_RESPONDEU,
  dias: DIAS_PADRAO,
  modeloId: null,
  // As ligações das variáveis do segundo modelo ({ '1': { source, value } }), como as do passo 2.
  ligacoes: {},
  texto,
  assunto,
});

/** Os modelos que dá para escolher na segunda mensagem (a ponte manda também os que não vão, apagados). */
export const modelosQueVao = modelos =>
  modelos.filter(modelo => !modelo.disabled);

/** Troca uma parte do reenvio sem mexer no objeto que veio. */
export const comMudanca = (reenvio, mudanca) => ({
  ...(reenvio || reenvioNovo()),
  ...mudanca,
});

/**
 * O que falta para a campanha poder sair com o reenvio ligado: null quando está pronto (ou desligado). `modelo` é o
 * modelo escolhido ({ variaveis }), para saber se toda variável dele tem de onde vir.
 */
export const faltaNoReenvio = (reenvio, canal, modelo = null) => {
  if (!reenvio) return null;
  const tipo = mensagemDoCanal(canal);
  if (tipo === MENSAGEM.MODELO && !reenvio.modeloId) return 'SEM_MODELO';
  if (
    tipo === MENSAGEM.MODELO &&
    !allBound(modelo?.variaveis || [], reenvio.ligacoes || {})
  )
    return 'SEM_LIGACAO';
  if (tipo === MENSAGEM.TEXTO && !reenvio.texto?.trim()) return 'SEM_TEXTO';
  if (tipo === MENSAGEM.ASSUNTO && !reenvio.assunto?.trim())
    return 'SEM_ASSUNTO';
  return null;
};

/** O reenvio que vale no canal: "não leu" vira "não respondeu" num canal que não avisa leitura. */
export const reenvioDoCanal = (reenvio, canal) => {
  if (!reenvio) return null;
  return quemPodeEscolher(canal).includes(reenvio.quem)
    ? reenvio
    : { ...reenvio, quem: QUEM.NAO_RESPONDEU };
};

/**
 * O reenvio no formato que o servidor grava (CampaignJourney::Reenvio): { reenvio_quem, reenvio_dias, reenvio_mensagem }.
 * Desligado, ou num canal sem reenvio, nada (o servidor desliga). `modelo`: no WhatsApp Oficial, a segunda mensagem já
 * montada pela página ({ modelo_id, template_params, ligacoes }); sem ela, nada (a revisão não deixa enviar assim).
 */
export const reenvioParaEnvio = (draft, { modelo = null } = {}) => {
  const tipo = mensagemDoCanal(draft.channel);
  const reenvio = reenvioDoCanal(draft.reenvio, draft.channel);
  if (!tipo || !reenvio) return {};
  const mensagem = {
    [MENSAGEM.MODELO]: modelo,
    [MENSAGEM.TEXTO]: { texto: String(reenvio.texto || '').trim() },
    [MENSAGEM.ASSUNTO]: { assunto: String(reenvio.assunto || '').trim() },
  }[tipo];
  if (!mensagem) return {};
  return {
    reenvio_quem: reenvio.quem,
    reenvio_dias: reenvio.dias,
    reenvio_mensagem: mensagem,
  };
};
