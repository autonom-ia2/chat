// #2451: a ação de webhook da macro manda a conversa para fora, como na regra automática (#2448). Criar ou mudar uma
// macro que tem (ou vai ter) webhook pede integration_manage (admin sempre); o servidor barra e a tela avisa antes.
export const MACRO_WEBHOOK = 'send_webhook_event';

export const usaWebhook = actions =>
  (actions || []).some(({ action_name }) => action_name === MACRO_WEBHOOK);

// As ações que o editor oferece: o webhook só para quem pode integrar, ou na macro que já o usa (para ela se ler inteira).
export const acoesOferecidas = (tipos, podeIntegrar, actions) =>
  tipos.filter(
    ({ key }) => podeIntegrar || key !== MACRO_WEBHOOK || usaWebhook(actions)
  );

// Salvar trava sem a chave quando a macro de agora ou a com que a tela abriu usa o webhook (tirá-lo também é mexer).
export const webhookTravado = (podeIntegrar, ...listas) =>
  !podeIntegrar && listas.some(usaWebhook);
