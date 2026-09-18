export const hasEditableMjml = bodyMjml =>
  typeof bodyMjml === 'string' && bodyMjml.trim().length > 0;

export const buildTemplateCampaignPayload = template => {
  if (!hasEditableMjml(template?.body_mjml)) return null;

  return {
    body_mjml: template.body_mjml,
    body_html: template.body_html || '',
  };
};
