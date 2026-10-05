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
};

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
  const base = { campaign_import_id: audienceId, channel };
  if (channel === 'whatsapp_cloud') {
    return {
      ...base,
      variable_bindings: bindings,
      variable_defaults: cleanDefaults(draft.defaults),
    };
  }
  if (channel === 'whatsapp_api') {
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
