// Modelos que a conversa consegue mandar (#1703, épico #1320). O filtro do
// Chatwoot (`isSendableTemplate` do @chatwoot/utils) só barra o tipo do
// componente LIST/PRODUCT/CATALOG, que a Meta não usa. No formato real, o
// produto vem como topo PRODUCT, botões SPM/MPM ou CATALOG, e o carrossel como
// um componente CAROUSEL. A conversa não leva produtos nem cartões: esses modelos
// só saem por campanha. Lido da estrutura do modelo, nunca do texto.
// O servidor confere de novo no envio (Whatsapp::Templates::ConversationSendGuard).
import { levaProdutos } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/produtosNaCampanha';

const maiusculo = valor => String(valor || '').toUpperCase();

const temCarrossel = template =>
  (template?.components || []).some(
    componente => maiusculo(componente?.type) === 'CAROUSEL'
  );

const temTopoDeProduto = template =>
  (template?.components || []).some(
    componente =>
      maiusculo(componente?.type) === 'HEADER' &&
      maiusculo(componente?.format) === 'PRODUCT'
  );

// Botão "Ver catálogo": o envio só o monta quando a campanha o traz.
const temBotaoDeCatalogo = template =>
  (template?.components || []).some(
    componente =>
      maiusculo(componente?.type) === 'BUTTONS' &&
      (componente.buttons || []).some(
        botao => maiusculo(botao?.type) === 'CATALOG'
      )
  );

export const vaiNaConversa = template =>
  !levaProdutos(template) &&
  !temTopoDeProduto(template) &&
  !temBotaoDeCatalogo(template) &&
  !temCarrossel(template);
