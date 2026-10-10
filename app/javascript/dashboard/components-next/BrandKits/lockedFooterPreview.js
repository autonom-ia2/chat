// What the canonical locked footer (#1081, lockedFooter.json) shows, read from its own MJML so the
// identity preview (#1076) never drifts from the footer the e-mail really gets.
import { LOCKED_FOOTER_MJML } from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/lockedFooter';

export const lockedFooterPreview = () => {
  const doc = new DOMParser().parseFromString(LOCKED_FOOTER_MJML, 'text/html');
  const section = doc.querySelector('mj-section');
  const text = doc.querySelector('mj-text');
  const link = text.querySelector('a');
  return {
    background: section.getAttribute('background-color'),
    color: text.getAttribute('color'),
    reason: text.firstChild.textContent.trim(),
    unsubscribe: link.textContent.trim(),
  };
};
