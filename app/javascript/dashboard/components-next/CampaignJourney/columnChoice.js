// "Colunas encontradas" of Novo público (#993, PRD §6.6-1, B2). Reads
// `schema_resolution` (contract in docs/campaigns/publicos/api-992.md §4–5) and builds the
// mapping sent to PATCH /campaign_imports/:id/columns: column indices or null per target.
export const COLUMN_TARGETS = ['name', 'phone', 'email', 'company'];

// ChoiceSelect value for "Não tem".
export const NO_COLUMN = 'none';

const STAT_BY_TARGET = {
  phone: 'valid_phone_count',
  email: 'valid_email_count',
};

const columnsOf = schemaResolution =>
  Array.isArray(schemaResolution?.columns) ? schemaResolution.columns : [];

const indexOrNull = value =>
  Number.isInteger(value) && value >= 0 ? value : null;

/** Mapping in use: the manual choice when there is one, else the suggested targets. */
export const currentMapping = (schemaResolution = {}) => {
  const manual = schemaResolution?.manual_mapping;
  return Object.fromEntries(
    COLUMN_TARGETS.map(target => [
      target,
      indexOrNull(
        manual
          ? manual[target]
          : (schemaResolution?.targets?.[target]?.column ?? null)
      ),
    ])
  );
};

/**
 * One row per target for the screen: bound column, its header, how many rows have a usable
 * value (valid phones for phone, valid e-mails for e-mail, filled cells otherwise), a masked
 * example when the backend sends one, and whether the suggestion was not certain.
 */
export const columnRows = (schemaResolution, mapping) => {
  const columns = columnsOf(schemaResolution);
  return COLUMN_TARGETS.map(target => {
    const index = mapping[target];
    const column = columns.find(item => item.index === index) || null;
    const statKey = STAT_BY_TARGET[target] || 'non_blank_count';
    return {
      target,
      index: column ? column.index : null,
      header: column?.header || null,
      count: column ? Number(column[statKey]) || 0 : 0,
      example: column?.example_masked || null,
      uncertain: schemaResolution?.targets?.[target]?.confident === false,
    };
  });
};

/** Options of the "Trocar" choice: every header of the sheet plus "Não tem". */
export const columnOptions = (schemaResolution, noneLabel) => [
  ...columnsOf(schemaResolution).map(column => ({
    value: String(column.index),
    label: column.header || `#${column.index + 1}`,
  })),
  { value: NO_COLUMN, label: noneLabel },
];

/**
 * New mapping with `target` bound to the chosen option. A column feeds one target only, so
 * a target that had the same column loses it (the API requires distinct indices).
 */
export const mappingWith = (mapping, target, optionValue) => {
  const index = optionValue === NO_COLUMN ? null : Number(optionValue);
  return Object.fromEntries(
    COLUMN_TARGETS.map(key => {
      if (key === target) return [key, index];
      if (index !== null && mapping[key] === index) return [key, null];
      return [key, mapping[key]];
    })
  );
};

/** The API needs a phone or an e-mail column. */
export const hasContactColumn = mapping =>
  mapping.phone !== null || mapping.email !== null;

export const sameMapping = (left, right) =>
  COLUMN_TARGETS.every(target => left[target] === right[target]);

/**
 * "Outras colunas": headers kept for the message. After validation the backend sends
 * `extra_columns`; while the columns are still being chosen they are the unbound headers.
 */
export const otherColumns = (campaignImport, mapping) => {
  if (campaignImport?.extra_columns?.length)
    return campaignImport.extra_columns;
  const bound = new Set(Object.values(mapping).filter(value => value !== null));
  return columnsOf(campaignImport?.schema_resolution)
    .filter(column => !bound.has(column.index))
    .map(column => column.header || `#${column.index + 1}`);
};
