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

export const HEADER_PREFIX = 'header.';
export const BUTTON_PREFIX = 'button.';

const componentOf = (template, type) =>
  (template?.components || []).find(component => component.type === type);

export const templateHeaderText = template => {
  const header = componentOf(template, COMPONENT_TYPES.HEADER);
  return header?.format === 'TEXT' ? header.text || '' : '';
};

/**
 * Variables of a template in template order, with their labels (#993): body ('1'), TEXT
 * header ('header.1') and URL buttons ('button.<index>'), the keys the backend expects
 * (CampaignJourney::TemplateVariableKeys).
 */
export const templateVariables = template => {
  const processed = buildTemplateParameters(template) || {};
  const bodyText = templateBodyText(template);
  const body = Object.keys(processed.body || {}).map(key => ({
    key,
    part: 'body',
    variable: key,
    label: variableLabel(bodyText, key),
  }));
  const headerText = templateHeaderText(template);
  const header = headerText
    ? Object.keys(processed.header || {}).map(key => ({
        key: `${HEADER_PREFIX}${key}`,
        part: 'header',
        variable: key,
        label: variableLabel(headerText, key),
      }))
    : [];
  const buttonTexts = (componentOf(template, 'BUTTONS')?.buttons || []).map(
    button => button.text || ''
  );
  const buttons = (processed.buttons || []).flatMap((button, index) =>
    button?.type === 'url'
      ? [
          {
            key: `${BUTTON_PREFIX}${index}`,
            part: 'button',
            variable: (button.variables || ['1'])[0],
            label: buttonTexts[index] || '',
          },
        ]
      : []
  );
  return [...body, ...header, ...buttons];
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
  if (field === 'first_name')
    return sample.first_name || firstName(sample.name);
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
  const valueOf = key => {
    const binding = bindings[key];
    if (!isBindingComplete(binding)) return '';
    if (binding.source === BINDING_SOURCES.FIXED) return binding.value;
    const value =
      binding.source === BINDING_SOURCES.COLUMN
        ? sample?.extra_values?.[binding.value] || ''
        : contactValue(binding.value, sample);
    return value || defaults[key] || placeholder(binding);
  };
  const variables = templateVariables(template);
  const valuesOf = part =>
    Object.fromEntries(
      variables
        .filter(variable => variable.part === part)
        .map(variable => [variable.variable, valueOf(variable.key)])
    );
  const header = renderTemplatePreview(
    templateHeaderText(template),
    valuesOf('header')
  );
  const body = renderTemplatePreview(
    templateBodyText(template),
    valuesOf('body')
  );
  return header ? `${header}\n\n${body}` : body;
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
