// A chave da OpenAI é o passo 1 do onboarding (épico #485): sem ela o CRM com
// IA, os agentes e o Guia da Plataforma ficam parados. Esta é a única
// definição de "a conta ainda precisa da chave" no frontend — a API nunca
// devolve a chave em si (visible_properties expõe só api_base e enabled), então
// o que dá para saber é se existe hook e se ele está ligado.

export const CRM_AI_INTEGRATION_ID = 'crm_kanban_ai';

/**
 * O hook está conectado e ligado?
 * @param {Object} hook - hook da integração, como vem da API
 * @returns {boolean}
 */
export const isHookActive = hook =>
  Boolean(hook) && hook.status !== false && hook.settings?.enabled !== false;

/**
 * A conta ainda precisa conectar a chave da OpenAI?
 * Vale tanto para hook ausente quanto para hook salvo com a IA desligada.
 * @param {Object} integration - integração `crm_kanban_ai`
 * @returns {boolean}
 */
export const isCrmAiKeyPending = integration =>
  !isHookActive(integration?.hooks?.[0]);
