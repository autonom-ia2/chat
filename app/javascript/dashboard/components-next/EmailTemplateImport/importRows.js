// What the result screen of "Trazer meu modelo" (#1099) says, built from the import the server
// returns: first what still blocks the saving (each with its own button), then what was solved,
// then what the import did. Sentences are i18n keys; fields go as chips, never as HTML.
const S = 'EMAIL_IMPORT.SCREEN';

// Our fields the person can put in place of one that does not exist here (server: Fixer::FIELDS).
export const FIELD_CHOICES = [
  'nome',
  'primeiro_nome',
  'email',
  'empresa',
  'cargo',
];
const QUALITY = [
  'button_height',
  'font_size',
  'contrast',
  'font_family',
  'image_alt',
];
const REMOVED = [
  'tracking_removed',
  'unsafe_removed',
  'unsafe_css_removed',
  'hidden_text_removed',
  'embed_removed',
  'template_code_removed',
  'platform_tags_removed',
];
const OWN_ROWS = [
  'images_to_copy',
  'images_copied',
  'tags_converted',
  'footer_replaced',
  'quality_fixed',
  ...REMOVED,
];
const FIXABLE = {
  image_missing: 'images',
  unresolved_parts: 'parts',
  unknown_fields: 'fields',
};

export const tagOf = key => `{{ ${key} }}`;

// A field as the person wrote it in the original ({{lead.cupom}}), from what the import recorded;
// our own way of writing it when the import has no record of it.
export const fieldText = (data, key) => {
  const unknown = (data?.report?.warnings || []).find(
    warning => warning.code === 'unknown_fields'
  );
  const item = (unknown?.items || []).find(entry => entry?.key === key);
  return item?.from || tagOf(key);
};
export const fieldLabelKey = key =>
  `${S}.FIELD_DIALOG.FIELDS.${key.toUpperCase()}`;

// -> [{ id, type: 'image' | 'part' | 'field' | 'invalid', ... }]
export const problemsOf = data => {
  const targets = data?.targets || { images: [], parts: [], fields: [] };
  const problems = [
    ...(targets.images || []).map(image => ({
      id: `image-${image.index}`,
      type: 'image',
      target: image.index,
      kind: image.kind,
      alt: image.alt,
    })),
    ...(targets.parts || []).map(part => ({
      id: `part-${part.id}`,
      type: 'part',
      target: part.id,
      text: part.text,
    })),
    ...(targets.fields || []).map(key => ({
      id: `field-${key}`,
      type: 'field',
      target: key,
      label: fieldText(data, key),
    })),
  ];
  const unfixable = (data?.blocking || []).some(
    entry =>
      !FIXABLE[entry.code] || !(targets[FIXABLE[entry.code]] || []).length
  );
  return unfixable
    ? [...problems, { id: 'invalid', type: 'invalid' }]
    : problems;
};

const problemRow = problem => {
  if (problem.type === 'image') {
    const background = problem.kind === 'background';
    let hint = null;
    if (background) hint = { key: `${S}.ROWS.BACKGROUND_MISSING_HINT` };
    else if (problem.alt) {
      hint = {
        key: `${S}.ROWS.IMAGE_MISSING_ALT`,
        params: { alt: problem.alt },
      };
    }
    return {
      id: problem.id,
      tone: 'warn',
      icon: 'i-lucide-image',
      text: {
        key: `${S}.ROWS.${background ? 'BACKGROUND_MISSING' : 'IMAGE_MISSING'}`,
      },
      hint,
      action: { label: `${S}.ROWS.SWAP_IMAGE`, problem },
    };
  }
  if (problem.type === 'part') {
    return {
      id: problem.id,
      tone: 'warn',
      icon: 'i-lucide-triangle-alert',
      text: { key: `${S}.ROWS.PART` },
      hint: { key: `${S}.ROWS.PART_HINT` },
      action: { label: `${S}.ROWS.SOLVE_PART`, problem },
    };
  }
  if (problem.type === 'field') {
    return {
      id: problem.id,
      tone: 'warn',
      icon: 'i-lucide-triangle-alert',
      text: { key: `${S}.ROWS.FIELD`, chips: { field: problem.label } },
      action: { label: `${S}.ROWS.CHOOSE`, problem },
    };
  }
  return {
    id: problem.id,
    tone: 'warn',
    icon: 'i-lucide-triangle-alert',
    text: { key: `${S}.ROWS.INVALID` },
    hint: { key: `${S}.ROWS.INVALID_HINT` },
    action: { label: `${S}.RESULT.ANOTHER`, problem },
  };
};

const imageUploadText = fix => {
  if (fix.kind === 'background') {
    return { key: `${S}.ROWS.FIXED.IMAGE_UPLOAD_BACKGROUND` };
  }
  if (!fix.target) return { key: `${S}.ROWS.FIXED.IMAGE_UPLOAD_PLAIN` };
  return {
    key: `${S}.ROWS.FIXED.IMAGE_UPLOAD`,
    params: { target: fix.target },
  };
};

const fixText = (fix, data) => {
  const field = { field: fieldText(data, fix.target) };
  const texts = {
    'image_missing.upload': imageUploadText(fix),
    'image_missing.remove': { key: `${S}.ROWS.FIXED.IMAGE_REMOVE` },
    'unknown_fields.field': {
      key: `${S}.ROWS.FIXED.FIELD_FIELD`,
      chips: field,
      fieldChoice: fix.value,
    },
    'unknown_fields.text': {
      key: `${S}.ROWS.FIXED.FIELD_TEXT`,
      chips: field,
      params: { text: fix.value },
    },
    'unknown_fields.remove': {
      key: `${S}.ROWS.FIXED.FIELD_REMOVE`,
      chips: field,
    },
    'unresolved_parts.text': { key: `${S}.ROWS.FIXED.PART_TEXT` },
    'unresolved_parts.remove': { key: `${S}.ROWS.FIXED.PART_REMOVE` },
  };
  return texts[`${fix.code}.${fix.choice}`];
};

const fixRows = data =>
  (data?.fixes || [])
    .map((fix, index) => ({
      id: `fix-${index}`,
      tone: 'ok',
      icon: 'i-lucide-check',
      text: fixText(fix, data),
    }))
    .filter(row => row.text);

const warningOf = (data, code) =>
  (data?.report?.warnings || []).find(warning => warning.code === code);

const doneRows = data => {
  const warnings = data?.report?.warnings || [];
  const rows = [];
  const copied = warningOf(data, 'images_copied');
  if (copied) {
    rows.push({
      id: 'images_copied',
      tone: 'ok',
      icon: 'i-lucide-check',
      text: { key: `${S}.ROWS.IMAGES_COPIED`, count: copied.count },
    });
  }
  const tags = warningOf(data, 'tags_converted');
  const firstTag = tags?.items?.find(item => item?.from && item?.to);
  if (firstTag) {
    const more = (tags.items?.length || 1) - 1;
    rows.push({
      id: 'tags_converted',
      tone: 'ok',
      icon: 'i-lucide-check',
      text: {
        key: `${S}.ROWS.TAG_SWAPPED`,
        chips: { from: firstTag.from, to: firstTag.to },
      },
      hint: more > 0 ? { key: `${S}.ROWS.TAG_MORE`, count: more } : null,
    });
  }
  rows.push({
    id: 'footer',
    tone: 'ok',
    icon: 'i-lucide-check',
    text: { key: `${S}.ROWS.FOOTER` },
    hint: warningOf(data, 'footer_replaced')
      ? { key: `${S}.ROWS.FOOTER_HINT` }
      : null,
  });
  (warningOf(data, 'quality_fixed')?.items || [])
    .filter(item => QUALITY.includes(item))
    .forEach(item =>
      rows.push({
        id: `quality-${item}`,
        tone: 'ok',
        icon: 'i-lucide-check',
        text: { key: `${S}.ROWS.QUALITY.${item.toUpperCase()}` },
      })
    );
  const removed = warnings.filter(warning => REMOVED.includes(warning.code));
  if (removed.length) {
    rows.push({
      id: 'removed',
      tone: 'info',
      icon: 'i-lucide-info',
      text: {
        key: `${S}.ROWS.REMOVED`,
        count: removed.reduce((sum, warning) => sum + (warning.count || 1), 0),
      },
      hint: {
        list: removed.map(
          warning => `${S}.ROWS.REMOVED_ITEMS.${warning.code.toUpperCase()}`
        ),
      },
    });
  }
  warnings
    .filter(
      warning =>
        warning.severity !== 'blocking' && !OWN_ROWS.includes(warning.code)
    )
    .forEach(warning =>
      rows.push({
        id: warning.code,
        tone: warning.severity === 'warning' ? 'info' : 'ok',
        icon:
          warning.severity === 'warning' ? 'i-lucide-info' : 'i-lucide-check',
        text: { key: warning.key, count: warning.count || 1 },
      })
    );
  return rows;
};

export const rowsOf = data => [
  ...problemsOf(data).map(problemRow),
  ...fixRows(data),
  ...doneRows(data),
];
