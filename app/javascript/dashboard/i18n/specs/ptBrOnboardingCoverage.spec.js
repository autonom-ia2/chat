import { describe, it, expect } from 'vitest';
import enAgents from '../locale/en/agents.json';
import ptAgents from '../locale/pt_BR/agents.json';
import enConversation from '../locale/en/conversation.json';
import ptConversation from '../locale/pt_BR/conversation.json';
import enSettings from '../locale/en/settings.json';
import ptSettings from '../locale/pt_BR/settings.json';
import enInboxMgmt from '../locale/en/inboxMgmt.json';
import ptInboxMgmt from '../locale/pt_BR/inboxMgmt.json';

// Chave sem tradução cai no inglês na tela. Estes são os grupos que o cliente
// atravessa no onboarding (perfil, canais, conversas, CRM, agentes). Canais e
// recursos que esta instalação não usa ficam de fora, listados em IGNORADOS.
const GRUPOS = [
  ['agents.json', enAgents, ptAgents, [/^AGENTS\./]],
  ['conversation.json', enConversation, ptConversation, [/^CONVERSATION\./]],
  [
    'settings.json',
    enSettings,
    ptSettings,
    [/^PROFILE_SETTINGS\./, /^SIDEBAR\./, /^COMPONENTS\./],
  ],
  [
    'inboxMgmt.json',
    enInboxMgmt,
    ptInboxMgmt,
    [/^INBOX_MGMT\.(ADD|FINISH|DETAILS|SETTINGS_POPUP)\./],
  ],
];

// Fora do escopo do onboarding desta instalação: Twilio/SMS, Captain, Shopify,
// widget de site e validação de identidade não são usados pelos clientes.
const IGNORADOS = [
  /TWILIO/i,
  /^INBOX_MGMT\.FINISH\.SMS/,
  /^INBOX_MGMT\.SETTINGS_POPUP\.IDENTITY_VALIDATION/,
  /CAPTAIN/i,
  /SHOPIFY/i,
];

const achatar = (objeto, prefixo = '') =>
  Object.entries(objeto).flatMap(([chave, valor]) =>
    valor && typeof valor === 'object' && !Array.isArray(valor)
      ? achatar(valor, `${prefixo}${chave}.`)
      : [[`${prefixo}${chave}`, valor]]
  );

describe('cobertura do pt_BR nas telas do onboarding', () => {
  it.each(GRUPOS)(
    '%s traduz tudo que a trilha mostra',
    (_arquivo, en, pt, escopos) => {
      const traduzidas = Object.fromEntries(achatar(pt));
      const faltando = achatar(en)
        .map(([chave]) => chave)
        .filter(chave => escopos.some(escopo => escopo.test(chave)))
        .filter(chave => !IGNORADOS.some(ignorado => ignorado.test(chave)))
        .filter(chave => !(chave in traduzidas));

      expect(faltando).toEqual([]);
    }
  );

  it.each(GRUPOS)(
    '%s não guarda tradução órfã, sem original em inglês',
    (_arquivo, en, pt, escopos) => {
      const originais = Object.fromEntries(achatar(en));
      const orfas = achatar(pt)
        .map(([chave]) => chave)
        .filter(chave => escopos.some(escopo => escopo.test(chave)))
        .filter(chave => !IGNORADOS.some(ignorado => ignorado.test(chave)))
        .filter(chave => !(chave in originais));

      expect(orfas).toEqual([]);
    }
  );
});
