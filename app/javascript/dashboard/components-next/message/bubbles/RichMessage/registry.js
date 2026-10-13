// Mensagens ricas enviadas ao cliente (chat#1473): a conversa mostra ao atendente o que o cliente recebeu.
// O formato vem em `content_attributes.rich_message.type` (aqui `contentAttributes.richMessage.type`,
// porque a lista de mensagens converte as chaves para camelCase); o corpo continua em `content`.
//
// Como acrescentar uma bolha (nenhum arquivo comum é editado, a não ser o catálogo de textos):
// 1. Crie `types/<Tipo>.vue` com o nome do tipo em PascalCase: `link_button` é `types/LinkButton.vue`,
//    `location_request` é `types/LocationRequest.vue`. Este arquivo acha a bolha pelo nome.
// 2. Leia a mensagem com `useMessageContext()` e monte com as peças comuns: `Frame.vue` (cabeçalho,
//    corpo e rodapé, e a interação embaixo) e `ActionRow.vue` (um botão como o cliente vê).
// 3. Textos em `i18n/locale/{en,pt_BR}/richMessage.json`, num bloco próprio `RICH_MESSAGE.<TIPO>`.
// 4. Teste em `specs/<Tipo>.spec.js`. Tipo sem arquivo em `types/` segue na bolha de antes (texto).
const modules = import.meta.glob('./types/*.vue', {
  eager: true,
  import: 'default',
});

const componentNameOf = path =>
  path.slice(path.lastIndexOf('/') + 1, -'.vue'.length);

const componentNameFor = type =>
  type
    .split('_')
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');

const bubbles = new Map(
  Object.entries(modules).map(([path, component]) => [
    componentNameOf(path),
    component,
  ])
);

export const richMessageBubbleFor = contentAttributes => {
  const type = contentAttributes?.richMessage?.type;
  if (typeof type !== 'string') return null;

  return bubbles.get(componentNameFor(type)) ?? null;
};
