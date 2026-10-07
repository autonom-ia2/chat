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
  // Identity of the e-mail (#1076): null = the default one.
  brandKitId: null,
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

// A draft holds work once it has a name, an audience, a channel or an e-mail on the server.
// An empty one is the same as no draft (#1093).
export const hasDraftWork = draft =>
  Boolean(
    draft &&
      (String(draft.title || '').trim() ||
        draft.audienceId ||
        draft.channel ||
        draft.emailCampaignId)
  );

// The address marks a journey in progress, so a reload keeps the work (#1093).
export const DRAFT_QUERY = 'draft';

// Where Nova campanha starts comes from the address, never silently from storage (#1093):
// - `returned=1`: back from Novo público (J3) → the stored draft, with the new audience;
// - `audience=<id>`: "Usar em nova campanha" (F3) → a fresh draft with that audience;
// - `email=<id>`: back from the editor → the stored draft when it holds that e-mail, else fresh;
// - `draft=1`: a reload in the middle → the stored draft;
// - nothing: a fresh draft, or `pending` when a draft with work waits for the person to choose.
export const journeyEntry = (query, stored) => {
  const audienceId = Number(query?.audience) || null;
  if (query?.returned === '1') {
    const base = stored || emptyDraft();
    return { draft: audienceId ? { ...base, audienceId, step: 1 } : base };
  }
  if (audienceId) return { draft: { ...emptyDraft(), audienceId, step: 1 } };
  if (query?.email) {
    const isSameEmail = stored?.emailCampaignId === Number(query.email);
    return { draft: isSameEmail ? stored : emptyDraft() };
  }
  if (query?.[DRAFT_QUERY] === '1') return { draft: stored || emptyDraft() };
  if (hasDraftWork(stored)) return { draft: null, pending: stored };
  return { draft: emptyDraft() };
};
