// A chave da OpenAI é o passo 1 do onboarding (épico #485): sem ela o CRM com
// IA, os agentes e o Guia da Plataforma ficam parados.

export const CRM_AI_INTEGRATION_ID = 'crm_kanban_ai';

/**
 * O hook está conectado e ligado?
 * A API nunca devolve a chave em si (visible_properties expõe só api_base e
 * enabled), então o que dá para ler aqui é o estado do hook.
 * @param {Object} hook - hook da integração, como vem da API
 * @returns {boolean}
 */
export const isHookActive = hook =>
  Boolean(hook) && hook.status !== false && hook.settings?.enabled !== false;

/**
 * A conta ainda precisa conectar a chave da OpenAI?
 *
 * Quem responde isso é o backend, no campo `enabled`: para esta integração ele
 * não é "existe hook", e sim o `Crm::Ai::CredentialResolver` — que aceita tanto
 * a chave da conta quanto a chave da instalação. Olhar só o hook faria a tela
 * pedir uma chave para contas onde a IA já funciona pela chave da instalação.
 *
 * @param {Object} integration - integração `crm_kanban_ai`
 * @returns {boolean}
 */
export const isCrmAiKeyPending = integration => integration?.enabled !== true;
