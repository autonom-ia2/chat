// "De onde vem cada parte da mensagem" of the WhatsApp Oficial step (#993, PRD §6.3, B1,
// B1b, D8). Each body variable of the approved template is bound to a contact field, a
// column of the audience or a fixed text. Template parsing comes from the same shared
// helpers the old WhatsApp dialog uses (dashboard/helper/templateHelper).
import {
  buildTemplateParameters,
  COMPONENT_TYPES,
  findComponentByType,
  renderTemplatePreview,
} from 'dashboard/helper/templateHelper';

export const BINDING_SOURCES = {
  CONTACT: 'contact',
  COLUMN: 'column',
  FIXED: 'fixed',
};

// Contact fields a variable can come from (i18n suffix under ...VARIABLES.CONTACT_FIELDS).
export const CONTACT_FIELDS = ['first_name', 'name', 'company'];

const LABEL_CONTEXT_CHARS = 60;

export const templateBodyText = template =>
  findComponentByType(template, COMPONENT_TYPES.BODY)?.text || '';

const isNumericKey = key => String(Number(key)) === String(key);

const LEADING_PUNCTUATION = ['!', '?', '.', ',', ';', ':', '-', ' '];

const trimLeadingPunctuation = text => {
  let start = 0;
  while (start < text.length && LEADING_PUNCTUATION.includes(text[start])) {
    start += 1;
  }
  return text.slice(start);
};

/**
 * What a variable stands for, sent to variable_suggestions as `label` (never contact data):
 * the name of a named variable, or the template text between the previous variable and
 * this one ("O seguro do seu carro vence em" for {{2}}), up to 60 characters.
 */
export const variableLabel = (bodyText, key) => {
  if (!isNumericKey(key)) return String(key).split('_').join(' ');
  const fallback = `{{${key}}}`;
  const position = bodyText.indexOf(fallback);
  if (position <= 0) return fallback;
  const before = bodyText.slice(0, position);
  const previousEnd = before.lastIndexOf('}}');
  const sinceVariable =
    previousEnd === -1 ? before : before.slice(previousEnd + 2);
  const context = sinceVariable.slice(-LABEL_CONTEXT_CHARS);
  const whole =
    context.length < sinceVariable.length
      ? context.slice(context.indexOf(' ') + 1)
      : context;
  return trimLeadingPunctuation(whole).trim() || fallback;
};

/** Body variables of a template, in template order, with their labels. */
export const templateVariables = template => {
  const body = buildTemplateParameters(template)?.body || {};
  const text = templateBodyText(template);
  return Object.keys(body).map(key => ({
    key,
    label: variableLabel(text, key),
  }));
};

/** Media header (image, video, document) the campaign needs a link for. */
export const mediaHeaderOf = template => {
  const header = buildTemplateParameters(template)?.header;
  return header && 'media_url' in header ? header : null;
};

/** Binding prefilled from a variable_suggestions item; null when there is none. */
export const bindingFromSuggestion = suggestion => {
  const source = suggestion?.source;
  if (!source) return null;
  if (source.source === 'name') {
    return { source: BINDING_SOURCES.CONTACT, value: 'name', suggested: true };
  }
  if (source.source === 'company') {
    return {
      source: BINDING_SOURCES.CONTACT,
      value: 'company',
      suggested: true,
    };
  }
  if (source.source === 'extra' && source.column) {
    return {
      source: BINDING_SOURCES.COLUMN,
      value: source.column,
      suggested: true,
    };
  }
  return null;
};

export const isBindingComplete = binding =>
  Boolean(binding?.source) && String(binding.value ?? '').trim() !== '';

export const allBound = (variables, bindings) =>
  variables.every(variable => isBindingComplete(bindings[variable.key]));

/**
 * Mapping for POST variable_coverage (api-992.md §7). Fixed texts are always present, so
 * they are not checked; contact name and first name read the name column.
 */
export const coverageMapping = bindings =>
  Object.fromEntries(
    Object.entries(bindings)
      .filter(([, binding]) => isBindingComplete(binding))
      .filter(([, binding]) => binding.source !== BINDING_SOURCES.FIXED)
      .map(([key, binding]) => {
        if (binding.source === BINDING_SOURCES.COLUMN) {
          return [key, { source: 'extra', column: binding.value }];
        }
        return [
          key,
          { source: binding.value === 'company' ? 'company' : 'name' },
        ];
      })
  );

/** Non-blank default texts only. */
export const cleanDefaults = defaults =>
  Object.fromEntries(
    Object.entries(defaults || {}).filter(
      ([, value]) => String(value ?? '').trim() !== ''
    )
  );

const firstName = name =>
  String(name || '')
    .trim()
    .split(' ')[0] || '';

const contactValue = (field, sample) => {
  if (!sample) return '';
  if (field === 'first_name') return firstName(sample.name);
  if (field === 'company') return sample.company_name || '';
  return sample.name || '';
};

/**
 * Text the first person of the audience would get ("Como o cliente vê"). Without a sample
 * (or a value) the default text, or the bracketed label of the source, takes its place.
 */
export const previewMessage = ({
  template,
  bindings,
  defaults = {},
  sample = null,
  placeholder,
}) => {
  const values = Object.fromEntries(
    templateVariables(template).map(({ key }) => {
      const binding = bindings[key];
      if (!isBindingComplete(binding)) return [key, ''];
      if (binding.source === BINDING_SOURCES.FIXED) {
        return [key, binding.value];
      }
      const value =
        binding.source === BINDING_SOURCES.COLUMN
          ? sample?.extra_values?.[binding.value] || ''
          : contactValue(binding.value, sample);
      return [key, value || defaults[key] || placeholder(binding)];
    })
  );
  return renderTemplatePreview(templateBodyText(template), values);
};

/** `template_params` in the shape the old WhatsApp dialog sends (api-993 §6). */
export const buildTemplateParams = ({ template, bindings, mediaUrl = '' }) => {
  const processed = buildTemplateParameters(template) || {};
  const body = processed.body
    ? Object.fromEntries(
        Object.keys(processed.body).map(key => {
          const binding = bindings[key];
          return [
            key,
            binding?.source === BINDING_SOURCES.FIXED ? binding.value : '',
          ];
        })
      )
    : undefined;
  const header = processed.header
    ? {
        ...processed.header,
        ...('media_url' in processed.header ? { media_url: mediaUrl } : {}),
      }
    : undefined;
  return {
    name: template.name,
    namespace: template.namespace || '',
    category: template.category || 'UTILITY',
    language: template.language || 'en_US',
    processed_params: {
      ...processed,
      ...(body ? { body } : {}),
      ...(header ? { header } : {}),
    },
  };
};

const bindingPayload = binding => ({
  source: binding.source,
  value: binding.value,
});

/** Body of POST /campaign_journey/campaigns (api-993-frontend-needs.md §6). */
export const buildCampaignPayload = ({
  audienceId,
  title,
  inboxId,
  scheduledAt,
  template,
  bindings,
  defaults,
  mediaUrl,
}) => ({
  campaign_import_id: audienceId,
  channel: 'whatsapp_cloud',
  campaign: {
    title: title.trim(),
    inbox_id: inboxId,
    scheduled_at: scheduledAt,
    template_params: buildTemplateParams({ template, bindings, mediaUrl }),
    variable_bindings: Object.fromEntries(
      templateVariables(template).map(({ key }) => [
        key,
        bindingPayload(bindings[key]),
      ])
    ),
    variable_defaults: cleanDefaults(defaults),
  },
});
