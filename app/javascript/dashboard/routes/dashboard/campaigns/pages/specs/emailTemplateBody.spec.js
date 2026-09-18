import { describe, expect, it } from 'vitest';

import {
  buildTemplateCampaignPayload,
  hasEditableMjml,
} from '../emailTemplateBody';

describe('emailTemplateBody', () => {
  it('accepts templates with editable MJML', () => {
    expect(hasEditableMjml('<mjml><mj-body /></mjml>')).toBe(true);
  });

  it('rejects blank or missing MJML', () => {
    expect(hasEditableMjml('   ')).toBe(false);
    expect(hasEditableMjml(null)).toBe(false);
    expect(hasEditableMjml(undefined)).toBe(false);
  });

  it('builds the campaign update payload from editable templates', () => {
    expect(
      buildTemplateCampaignPayload({
        body_mjml: '<mjml><mj-body /></mjml>',
        body_html: '<html></html>',
      })
    ).toEqual({
      body_mjml: '<mjml><mj-body /></mjml>',
      body_html: '<html></html>',
    });
  });

  it('does not build a payload for preview-only templates', () => {
    expect(
      buildTemplateCampaignPayload({
        body_mjml: '',
        body_html: '<html>preview only</html>',
      })
    ).toBeNull();
  });
});
