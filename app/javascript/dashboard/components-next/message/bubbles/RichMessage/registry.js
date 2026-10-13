// Mensagens ricas enviadas ao cliente (chat#1473): a conversa mostra ao atendente o que o cliente recebeu.
// O formato vem em `content_attributes.rich_message.type` (aqui `contentAttributes.richMessage.type`);
// o corpo continua em `content`. Só mensagem que foi ao canal (não privada, de saída ou modelo) ganha bolha.
//
// Como acrescentar uma bolha (só os dois catálogos de texto são comuns):
// 1. Crie `types/<Tipo>.vue` com o tipo exato em PascalCase: `link_button` é `types/LinkButton.vue`,
//    `location_request` é `types/LocationRequest.vue`. Todo `.vue` em `types/` vira bolha: peça auxiliar
//    do tipo fica FORA de `types/` (ex.: `RichMessage/<Tipo>Item.vue`).
// 2. Leia a mensagem com `useMessageContext()` e monte com `Frame.vue` (cabeçalho, corpo, rodapé e anexos;
//    slot `header` para cabeçalho próprio) e `ActionRow.vue` (o botão como o cliente vê; slot padrão no
//    lugar do rótulo e slot `trailing` à direita).
// 3. Textos só dentro do bloco reservado do tipo, `RICH_MESSAGE.<TIPO>`, em `i18n/locale/{en,pt_BR}/richMessage.json`.
// 4. Teste em `specs/<Tipo>.spec.js`, montando com `message/specs/montarMensagem.js`; não edite
//    `Message.spec.js` nem `registry.spec.js`.
// 5. Não edite `Message.vue`, `Frame.vue`, `ActionRow.vue` nem este arquivo; se precisar, pare e relate.
// 6. A lista de mensagens converte as chaves de `rich_message` para camelCase em profundidade: a bolha não
//    desenha nem depende de mapas com chaves livres (ex.: dados de formulário).
// Tipo sem arquivo em `types/` segue na bolha de antes (texto).
import { MESSAGE_TYPES } from '../../constants';

const CHANNEL_MESSAGE_TYPES = [MESSAGE_TYPES.OUTGOING, MESSAGE_TYPES.TEMPLATE];

const modules = import.meta.glob('./types/*.vue', {
  eager: true,
  import: 'default',
});

const componentNameOf = path =>
  path.slice(path.lastIndexOf('/') + 1, -'.vue'.length);

// 'LinkButton' vira 'link_button': cada maiúscula abre uma palavra. A chave é o tipo exato que o envio aceita.
const typeOf = componentName =>
  [...componentName]
    .map((char, index) => {
      const lower = char.toLowerCase();
      if (char === lower || index === 0) return lower;
      return `_${lower}`;
    })
    .join('');

const bubbles = new Map(
  Object.entries(modules).map(([path, component]) => [
    typeOf(componentNameOf(path)),
    component,
  ])
);

export const richMessageBubbleFor = message => {
  if (message.private || !CHANNEL_MESSAGE_TYPES.includes(message.messageType))
    return null;

  const type = message.contentAttributes?.richMessage?.type;
  if (typeof type !== 'string') return null;

  return bubbles.get(type) ?? null;
};
