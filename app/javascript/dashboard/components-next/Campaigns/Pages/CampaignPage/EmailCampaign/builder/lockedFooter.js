// The locked footer (#1081): lockedFooter.json is the single source, shared with the server
// (EmailCampaigns::LockedFooter: AI prompt and sanitizer fallback). Plain string scanning — no regex.
import footer from './lockedFooter.json';

export const LOCKED_FOOTER_MJML = footer.mjml;

const afterOpenTag = (mjml, tag) =>
  mjml.indexOf('>', mjml.indexOf(`<${tag}`)) + 1;

const insertAt = (mjml, index, markup) =>
  mjml.slice(0, index) + markup + mjml.slice(index);

// Footer of the editor (block and starter e-mail): the locked footer plus placeholders the person
// edits on the canvas — a company line and, for the block, social icons pointing at each network.
export const editableFooterMjml = ({ social = false } = {}) => {
  const withIdentity = insertAt(
    LOCKED_FOOTER_MJML,
    afterOpenTag(LOCKED_FOOTER_MJML, 'mj-text'),
    `${footer.identity_placeholder}<br/>`
  );
  if (!social) return withIdentity;
  return insertAt(
    withIdentity,
    afterOpenTag(withIdentity, 'mj-column'),
    footer.social_placeholder
  );
};
