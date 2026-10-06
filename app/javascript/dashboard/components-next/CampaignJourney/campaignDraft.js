// Draft of "Nova campanha" (#993, PRD §6.2, J2–J3). Lives only in this browser, one per
// account: `campaignJourney:draft:<accountId>` (docs/campaigns/publicos/
// api-993-frontend-needs.md §7). Holds choices, never contact data. Storage can be blocked
// (private window, policies): every access is guarded and the journey works without it.
export const DRAFT_VERSION = 1;

export const draftKey = accountId => `campaignJourney:draft:${accountId}`;

export const emptyDraft = () => ({
  version: DRAFT_VERSION,
  title: '',
  audienceId: null,
  channel: '',
  inboxId: null,
  templateId: null,
  mediaUrl: '',
  bindings: {},
  defaults: {},
  // WhatsApp API (#999)
  messageBody: '',
  apiTemplateId: null,
  // E-mail (#999): "identity:<id>" or "inbox:<id>", and the draft created on the server
  emailSender: '',
  fromName: '',
  fromEmail: '',
  replyInboxId: null,
  emailCampaignId: null,
  when: 'now',
  scheduledAt: '',
  step: 1,
});

const defaultStorage = () => {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
};

export const loadDraft = (accountId, storage = defaultStorage()) => {
  try {
    const raw = storage?.getItem(draftKey(accountId));
    if (!raw) return null;
    const draft = JSON.parse(raw);
    if (draft?.version !== DRAFT_VERSION) return null;
    return { ...emptyDraft(), ...draft };
  } catch {
    return null;
  }
};

export const saveDraft = (accountId, draft, storage = defaultStorage()) => {
  try {
    storage?.setItem(
      draftKey(accountId),
      JSON.stringify({ ...draft, version: DRAFT_VERSION })
    );
    return true;
  } catch {
    return false;
  }
};

export const clearDraft = (accountId, storage = defaultStorage()) => {
  try {
    storage?.removeItem(draftKey(accountId));
  } catch {
    // Nothing to clear when storage is blocked.
  }
};
