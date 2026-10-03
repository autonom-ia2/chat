// Guia da Plataforma V2 — highlight allow-list. Maps a backend `highlight` anchor (from the KB flow's
// `highlight:` field) to HOW to find the on-screen element. Centralized on purpose (the app barely uses
// data-testid): adding a target = one entry here + a `highlight:` line in the KB flow. No edits scattered
// across components → safe across Chatwoot upgrades.
//
// Resolver spec per anchor:
//   { text: 'Visible label', tags: ['button','a'] } → first VISIBLE element of those tags whose
//     normalized text contains the label (default tags: button, a). For inputs, the placeholder is used.
// All texts are the EXACT rendered pt_BR labels (verified to exist in the pt_BR locale).
export const GUIDE_HIGHLIGHT_REGISTRY = {
  // CRM Kanban
  'crm-new-pipeline': { text: 'Novo funil' },
  'crm-new-card': { text: 'Nova oportunidade' },
  'crm-filters': { text: 'Filtros' },
  'crm-configure-inboxes': { text: 'Configurar caixas de entrada' },
  // CRM outras telas
  'crm-new-sla': { text: 'Nova política' },
  'crm-new-token': { text: 'Criar token' },
  'crm-n8n-token': { text: 'Criar token de API do CRM' },
  // Configurações
  'settings-add-agent': { text: 'Adicionar Agente' },
  'settings-add-role': { text: 'Adicionar função personalizada' },
  'settings-new-team': { text: 'Criar novo time' },
  'settings-add-automation': { text: 'Criar Automação' },
  'settings-add-canned': { text: 'Adicionar resposta pronta' },
  'settings-add-label': { text: 'Adicionar etiqueta' },
  'settings-add-attribute': { text: 'Criar atributo personalizado' },
  'settings-add-bot': { text: 'Criar Robô' },
  'settings-add-webhook': { text: 'Adicionar novo Webhook' },
  // Relatórios
  'reports-download-sla': { text: 'Baixar relatórios de SLA' },
  // Campanhas
  'campaigns-new-email': { text: 'Nova campanha de e-mail' },
  'campaigns-add-sender': { text: 'Adicionar domínio de envio' },
  'campaigns-new-whatsapp': { text: 'Criar campanha' },
  // Agentes Autonom.ia
  'agents-create': { text: 'Criar agente com IA' },
  // Busca global (input)
  'global-search': {
    text: 'Digite 3 ou mais caracteres para pesquisar',
    tags: ['input'],
  },
  // --- cobertura ampliada (workflow) ---
  'conversations-advanced-filter': { selector: 'button .i-lucide-list-filter' },
  'conversations-sort-status': { selector: 'button .i-lucide-arrow-up-down' },
  'conversations-compose-new': { selector: 'button .i-lucide-pen-line' },
  'contacts-more-actions': {
    selector: 'header button .i-lucide-ellipsis-vertical',
  },
  'contacts-open-filter': { selector: '#toggleContactsFilterButton' },
  'contacts-sort-menu': { selector: 'header button .i-lucide-arrow-down-up' },
  'campaign-imports-back-to-contacts': {
    text: 'Voltar para contatos',
    tags: ['button'],
  },
  'campaign-imports-history-title': {
    text: 'Histórico de bases de campanha',
    tags: ['h1'],
  },
  'settings-account-save': {
    text: 'Atualizar configurações',
    tags: ['button'],
  },
  'profile-update-basic': { text: 'Atualizar o Perfil', tags: ['button'] },
  'profile-change-password': { text: 'Mudar Senha', tags: ['button'] },
  'profile-copy-access-token': { text: 'Copiar', tags: ['button'] },
  'reports-download-agents': { text: 'Baixar relatórios de agentes' },
  'reports-download-inboxes': { text: 'Baixar relatórios de entrada' },
  'reports-download-teams': { text: 'Baixar relatórios de time' },
  'reports-download-labels': { text: 'Baixar relatórios de etiquetas' },
  'reports-download-csat': { text: 'Baixar relatórios de CSAT' },
  'campaigns-new-sms': { text: 'Criar campanha' },
  'campaigns-new-livechat': { text: 'Criar campanha' },
  'campaigns-new-whatsapp-official': { text: 'Criar campanha' },
  'crm-booking-page': { text: 'Página de agendamento', tags: ['button'] },
  // --- canais (Configurações > Caixas de entrada > Nova caixa) ---
  'channel-whatsapp-oficial': {
    text: 'WhatsApp Oficial',
    tags: ['h3'],
  },
  'channel-whatsapp-api': {
    text: 'WhatsApp API',
    tags: ['h3'],
  },
  'channel-email': { text: 'E-mail', tags: ['h3'] },
  'channel-instagram': { text: 'Instagram', tags: ['h3'] },
  'channel-facebook': { text: 'Facebook', tags: ['h3'] },
  'channel-website': { text: 'Site', tags: ['h3'] },
  'channel-sms': { text: 'SMS', tags: ['h3'] },
  'channel-telegram': { text: 'Telegram', tags: ['h3'] },
  'channel-api': { text: 'API', tags: ['h3'] },
};

const normalize = s => (s || '').replace(/\s+/g, ' ').trim().toLowerCase();

const isVisible = el => {
  if (!el || el.offsetParent === null || el.getClientRects().length === 0) {
    return false;
  }
  // Reject elements hidden via visibility/opacity (offsetParent alone misses these) so a selector
  // never matches an invisible duplicate (e.g. an `invisible opacity-0` sidebar icon button).
  const cs = getComputedStyle(el);
  return cs.visibility !== 'hidden' && cs.opacity !== '0';
};

// Text to match against, per element: inputs use placeholder/value, others use textContent.
const elementText = el =>
  el.tagName === 'INPUT' || el.tagName === 'TEXTAREA'
    ? el.placeholder || el.value || ''
    : el.textContent;

// Resolve an anchor to a live, visible DOM element (or null). Allow-list only.
//  - { selector } → first VISIBLE element matching the CSS selector (for icon-only controls).
//  - { text }     → first VISIBLE element (default tags button/a; inputs by placeholder) whose label
//                   EXACTLY matches (not substring) so a generic/short label never grabs a longer or
//                   unrelated control — avoids wrong-element highlights.
export const resolveHighlightElement = anchor => {
  const spec = GUIDE_HIGHLIGHT_REGISTRY[anchor];
  if (!spec) return null;

  if (spec.selector) {
    return (
      Array.from(document.querySelectorAll(spec.selector)).find(isVisible) ||
      null
    );
  }
  if (!spec.text) return null;

  const tags = spec.tags || ['button', 'a'];
  const target = normalize(spec.text);
  return (
    Array.from(document.querySelectorAll(tags.join(','))).find(
      el => isVisible(el) && normalize(elementText(el)) === target
    ) || null
  );
};
