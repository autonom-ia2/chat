// What Novo público shows about an audience before and after "Salvar público" (#993, PRD
// §6.6, B5, B6, J5, J6, C1–C6). Pure functions over the campaign_import object.
import { AUDIENCE_CHANNELS } from './audienceRows';

// Still working in the background: the page keeps polling.
export const CHECKING_STATUSES = ['uploaded', 'validating'];
export const SAVING_STATUSES = ['queued', 'importing'];
export const SAVED_STATUSES = ['completed', 'completed_with_failures'];
export const REVIEW_STATUSES = [
  'needs_column_choice',
  'ready_to_confirm',
  'validation_failed',
];

export const PHASES = {
  UPLOAD: 'upload',
  CHECKING: 'checking',
  REVIEW: 'review',
  SAVING: 'saving',
  DONE: 'done',
  FAILED: 'failed',
};

export const phaseOf = campaignImport => {
  const status = campaignImport?.status;
  if (!status) return PHASES.UPLOAD;
  if (CHECKING_STATUSES.includes(status)) return PHASES.CHECKING;
  if (REVIEW_STATUSES.includes(status)) return PHASES.REVIEW;
  if (SAVING_STATUSES.includes(status)) return PHASES.SAVING;
  if (SAVED_STATUSES.includes(status)) return PHASES.DONE;
  return PHASES.FAILED;
};

export const isSavedAudience = campaignImport =>
  SAVED_STATUSES.includes(campaignImport?.status);

/** "98 prontos · 2 com problema" (B5). */
export const peopleSummary = campaignImport => ({
  ready: Number(campaignImport?.valid_rows) || 0,
  problems: Number(campaignImport?.invalid_rows) || 0,
});

// Row reasons the screen knows how to say (api-993-frontend-needs.md §2). Anything else
// is shown as "Outro problema".
export const REASON_KEYS = {
  missing_contact: 'MISSING_CONTACT',
  invalid_brazilian_mobile_number: 'INVALID_PHONE',
  blank_phone_number: 'BLANK_PHONE',
  formula_phone_number: 'FORMULA',
  formula_detected: 'FORMULA',
  invalid_email: 'INVALID_EMAIL',
  blank_email: 'BLANK_EMAIL',
  duplicate_phone_in_file: 'DUPLICATE_PHONE',
  duplicate_email_in_file: 'DUPLICATE_EMAIL',
  no_valid_rows: 'NO_VALID_ROWS',
  row_limit_exceeded: 'ROW_LIMIT',
  empty_file: 'EMPTY_FILE',
};

export const reasonKey = code => REASON_KEYS[code] || 'OTHER';

/** Reasons with how many rows each, most frequent first (fallback for B5 without rows). */
export const reasonTally = campaignImport => {
  const errors = campaignImport?.validation_summary?.errors;
  if (!errors || typeof errors !== 'object') return [];
  return Object.entries(errors)
    .map(([code, count]) => ({ code, key: reasonKey(code), count: +count }))
    .filter(item => item.count > 0)
    .sort((a, b) => b.count - a.count);
};

/**
 * Channel switches (J5, J6): both channels always listed. A channel with no valid value
 * shows off with "sem dados" and cannot be switched on.
 */
export const channelSwitches = channels =>
  AUDIENCE_CHANNELS.map(channel => {
    const count = Number(channels?.[channel]?.count) || 0;
    return {
      channel,
      count,
      hasData: count > 0,
      enabled: count > 0 && channels?.[channel]?.enabled !== false,
    };
  });

const companyColumnHeader = campaignImport => {
  const resolution = campaignImport?.schema_resolution || {};
  const index = resolution.manual_mapping
    ? resolution.manual_mapping.company
    : resolution.targets?.company?.column;
  if (index === null || index === undefined) return null;
  return (
    (resolution.columns || []).find(column => column.index === index)?.header ||
    null
  );
};

const hasNumbers = source =>
  Boolean(source) &&
  ['created', 'reused', 'linked', 'kept'].some(key =>
    Number.isFinite(Number(source[key]))
  );

/**
 * Empresas block (api-992.md §9, C1–C6). Before saving, `validation_summary.companies`
 * says what saving will do; after saving, `companies` has the final numbers. `null` hides
 * the block: `available: false` (account without companies) or no company column.
 */
export const companiesBlock = campaignImport => {
  const preview = campaignImport?.validation_summary?.companies;
  if (!preview || preview.available === false) return null;
  const column = companyColumnHeader(campaignImport);
  if (!column) return null;
  const finals = campaignImport.companies;
  const result = {
    created: finals?.created,
    reused: finals?.reused,
    linked: finals?.contacts_linked,
    kept: finals?.kept,
  };
  return {
    column,
    create: campaignImport.create_companies !== false,
    preview: {
      created: preview.companies_created,
      reused: preview.companies_reused,
      linked: preview.contacts_linked,
      kept: preview.contacts_kept,
    },
    result:
      SAVED_STATUSES.includes(campaignImport.status) && hasNumbers(result)
        ? result
        : null,
  };
};

/** True when every row was refused: the file cannot be saved (B6). */
export const isRefused = campaignImport =>
  campaignImport?.status === 'validation_failed';
