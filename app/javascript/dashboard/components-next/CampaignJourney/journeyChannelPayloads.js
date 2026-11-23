// Request bodies of POST /campaign_journey/campaigns for WhatsApp API and e-mail (#993 front of
// #999, docs/campaigns/publicos/api-999.md §2.2–2.3) and of POST recipient_previews.
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { CAMPAIGN_CHANNELS } from './campaignChannels';
import { cleanDefaults } from './templateVariables';

// Journey channel → `channel` of the backend.
export const BACKEND_CHANNEL = {
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: 'whatsapp_cloud',
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: 'whatsapp_api',
  [CAMPAIGN_CHANNELS.EMAIL]: 'email',
  [CAMPAIGN_CHANNELS.SMS]: 'sms',
};

// #1004: Bandwidth SMS, or Twilio with the sms medium (Twilio WhatsApp does not count).
export const isSmsInbox = inbox =>
  inbox.channel_type === INBOX_TYPES.SMS ||
  (inbox.channel_type === INBOX_TYPES.TWILIO && inbox.medium === 'sms');

export const isWhatsappApiCampaignInbox = inbox =>
  inbox.channel_type === INBOX_TYPES.API &&
  inbox.additional_attributes?.campaign_channel_type === 'whatsapp_api';

/** Defaults only for the fields the message still uses. */
const usedDefaults = (messageBody, defaults) =>
  Object.fromEntries(
    Object.entries(cleanDefaults(defaults)).filter(([token]) =>
      String(messageBody || '').includes(`{{${token}}}`)
    )
  );

// #3099: a versão 2 de cada canal, no formato que o servidor confere (CampaignJourney::DuasVersoes::Segunda): outro
// modelo no WhatsApp Oficial (D3), outro assunto no e-mail (D2) e outro texto no SMS e na WhatsApp API.
const segundaDoCanal = (draft, modelo) => {
  const versoes = draft.duasVersoes;
  if (draft.channel === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL) {
    return {
      template_name: modelo?.name || '',
      template_language: modelo?.language || '',
    };
  }
  if (draft.channel === CAMPAIGN_CHANNELS.EMAIL) {
    return { subject: String(versoes.assunto || '').trim() };
  }
  const texto = versoes.texto || '';
  return {
    message_body: texto,
    variable_defaults: usedDefaults(texto, draft.defaults),
  };
};

/**
 * #3099: com "Testar duas versões" ligado, a regra e a versão 2 ({ duas_versoes }); desligado, nada.
 * `modelo`: o modelo da versão 2 no WhatsApp Oficial (o rascunho só guarda o id).
 */
export const duasVersoesParaEnvio = (draft, { modelo = null } = {}) => {
  const versoes = draft.duasVersoes;
  if (!versoes?.ligado) return {};
  return {
    duas_versoes: {
      criterio: versoes.criterio,
      divisao: versoes.divisao,
      espera_horas: versoes.espera,
      segunda: segundaDoCanal(draft, modelo),
    },
  };
};

/**
 * #3098: "Quem comprou depois" da revisão (dias da janela e porcentagem do grupo de controle).
 * #3099: e as duas versões da mensagem, quando ligadas (duasVersoesParaEnvio).
 */
export const medicaoDaCampanha = (draft, { modelo = null } = {}) => ({
  janela_de_compra_dias: draft.janelaDeCompra || 7,
  grupo_de_controle_pct: draft.grupoDeControle || 0,
  ...duasVersoesParaEnvio(draft, { modelo }),
});

// #3099: com as duas versões ligadas, o "Vão receber" volta também com o plano do teste contado pelo servidor
// (`duas_versoes` do payload), já sem o grupo de controle escolhido na revisão.
const planoNoPreview = draft =>
  draft.duasVersoes?.ligado
    ? {
        duas_versoes: { divisao: draft.duasVersoes.divisao },
        grupo_de_controle_pct: draft.grupoDeControle || 0,
      }
    : {};

export const buildWhatsappApiPayload = ({
  audienceId,
  draft,
  scheduledAt,
}) => ({
  campaign_import_id: audienceId,
  channel: 'whatsapp_api',
  campaign: {
    title: draft.title.trim(),
    inbox_id: draft.inboxId,
    scheduled_at: scheduledAt,
    message_body: draft.messageBody,
    ...(draft.apiTemplateId ? { template_id: draft.apiTemplateId } : {}),
    variable_defaults: usedDefaults(draft.messageBody, draft.defaults),
    ...medicaoDaCampanha(draft),
  },
});

/** SMS (api-1004.md §4): message with fields and the defaults it uses. */
export const buildSmsPayload = ({ audienceId, draft, scheduledAt }) => ({
  campaign_import_id: audienceId,
  channel: 'sms',
  campaign: {
    title: draft.title.trim(),
    inbox_id: draft.inboxId,
    scheduled_at: scheduledAt,
    message: draft.messageBody,
    variable_defaults: usedDefaults(draft.messageBody, draft.defaults),
    ...medicaoDaCampanha(draft),
  },
});

/** `emailSender` is "identity:<id>" (verified domain) or "inbox:<id>" (direct send). */
export const buildEmailPayload = ({ audienceId, draft }) => {
  const [kind, id] = String(draft.emailSender || '').split(':');
  const isDomain = kind === 'identity';
  return {
    campaign_import_id: audienceId,
    channel: 'email',
    campaign: {
      title: draft.title.trim(),
      delivery_mode: isDomain ? 'ses' : 'direct_inbox',
      ...(isDomain
        ? { sender_identity_id: Number(id), from_email: draft.fromEmail.trim() }
        : { sender_inbox_id: Number(id) }),
      ...(draft.fromName?.trim() ? { from_name: draft.fromName.trim() } : {}),
      ...(draft.replyInboxId ? { reply_to_inbox_id: draft.replyInboxId } : {}),
    },
  };
};

export const buildPreviewPayload = ({ audienceId, draft, bindings }) => {
  const channel = BACKEND_CHANNEL[draft.channel];
  const base = {
    campaign_import_id: audienceId,
    channel,
    ...planoNoPreview(draft),
  };
  if (channel === 'whatsapp_cloud') {
    return {
      ...base,
      variable_bindings: bindings,
      variable_defaults: cleanDefaults(draft.defaults),
    };
  }
  if (channel === 'whatsapp_api' || channel === 'sms') {
    return {
      ...base,
      message_body: draft.messageBody || '',
      variable_defaults: usedDefaults(draft.messageBody, draft.defaults),
    };
  }
  return base;
};

/** E-mail readiness checks of the engine as [{ key, ok }] (send_readiness.checks). */
export const emailChecks = emailCampaign =>
  Object.entries(emailCampaign?.send_readiness?.checks || {}).map(
    ([key, ok]) => ({ key, ok: ok === true })
  );
