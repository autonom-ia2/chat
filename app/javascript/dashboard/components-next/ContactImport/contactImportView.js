// Importar contatos (#1006): what the screen shows for a contact import, from the
// campaign_import payload (flow "contacts"). Pure functions, tested in specs/.

export const TARGETS = ['name', 'phone', 'email', 'company'];
export const CONTACT_TARGETS = ['phone', 'email'];

// The value ChoiceSelect uses for "Não tem".
export const NO_COLUMN = '';

const READING = ['uploaded', 'validating'];
const IMPORTING = ['confirmed', 'queued', 'importing'];
const REVIEW = ['needs_column_choice', 'ready_to_confirm', 'validation_failed'];
const DONE = ['completed', 'completed_with_failures'];

// upload → reading → review → importing → done (or failed).
export const stageFor = contactImport => {
  const status = contactImport?.status;
  if (!status) return 'upload';
  if (READING.includes(status)) return 'reading';
  if (REVIEW.includes(status)) return 'review';
  if (IMPORTING.includes(status)) return 'importing';
  if (DONE.includes(status)) return 'done';
  return 'failed';
};

export const isPolling = contactImport =>
  ['reading', 'importing'].includes(stageFor(contactImport));

const resolutionOf = contactImport => contactImport?.schema_resolution || {};

export const columnsOf = contactImport =>
  Array.isArray(resolutionOf(contactImport).columns)
    ? resolutionOf(contactImport).columns
    : [];

// The columns as they are now: the person's choice, else what the reader found or suggested.
export const currentMapping = contactImport => {
  const resolution = resolutionOf(contactImport);
  const manual = resolution.manual_mapping;
  return Object.fromEntries(
    TARGETS.map(target => {
      const index = manual
        ? manual[target]
        : resolution.targets?.[target]?.column;
      return [target, Number.isInteger(index) ? index : NO_COLUMN];
    })
  );
};

export const sameMapping = (left, right) =>
  TARGETS.every(target => left[target] === right[target]);

export const hasContactColumn = mapping =>
  CONTACT_TARGETS.some(target => mapping[target] !== NO_COLUMN);

// The body of PATCH .../columns: index or null.
export const mappingPayload = mapping =>
  Object.fromEntries(
    TARGETS.map(target => [
      target,
      mapping[target] === NO_COLUMN ? null : mapping[target],
    ])
  );

// Companies are hidden when the account has no companies feature (C6).
export const companiesAvailable = contactImport =>
  contactImport?.validation_summary?.companies?.available !== false;

export const visibleTargets = contactImport =>
  companiesAvailable(contactImport)
    ? TARGETS
    : TARGETS.filter(target => target !== 'company');

export const columnLabel = (column, fallback) =>
  column?.header?.trim() ? column.header : fallback((column?.index ?? 0) + 1);

// Evidence shown next to a chosen column: valid mobiles/e-mails, otherwise filled cells.
export const columnEvidence = (target, column) => {
  if (!column) return null;
  if (target === 'phone')
    return { kind: 'VALID', count: column.valid_phone_count };
  if (target === 'email')
    return { kind: 'VALID', count: column.valid_email_count };
  return { kind: 'FILLED', count: column.non_blank_count };
};

export const peopleCounts = contactImport => {
  const ready = contactImport?.valid_rows || 0;
  const existing = contactImport?.validation_summary?.existing_contacts || 0;
  return {
    ready,
    existing,
    created: Math.max(ready - existing, 0),
    problems: contactImport?.invalid_rows || 0,
  };
};

export const attributeColumns = contactImport =>
  contactImport?.validation_summary?.contact_attributes || [];

export const companyPreview = contactImport => {
  const preview = contactImport?.validation_summary?.companies || {};
  return {
    created: preview.companies_created || 0,
    reused: preview.companies_reused || 0,
    linked: preview.contacts_linked || 0,
    kept: preview.contacts_kept || 0,
  };
};

// Reasons of a refused file (validation_failed): the global ones, without the per-row tally.
export const globalErrors = contactImport =>
  Object.keys(contactImport?.validation_summary?.errors || {});

export const resultCounts = contactImport => {
  const imported = contactImport?.imported_contacts_count || 0;
  return {
    imported,
    created: Math.max(
      imported - (contactImport?.existing_contacts_count || 0),
      0
    ),
    companies: contactImport?.companies?.created || 0,
    attributes:
      contactImport?.validation_summary?.contact_attributes_created || 0,
    failed:
      (contactImport?.failed_contacts_count || 0) +
      (contactImport?.invalid_rows || 0),
  };
};
