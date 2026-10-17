// Modelos que a conversa consegue mandar (#1703, épico #1320). O filtro do
// Chatwoot (`isSendableTemplate` do @chatwoot/utils) só barra o tipo do
// componente LIST/PRODUCT/CATALOG, que a Meta não usa. No formato real, o
// produto vem como topo PRODUCT, botões SPM/MPM ou CATALOG, e o carrossel como
// um componente CAROUSEL. Fora da conversa (#1716), a tela não leva produtos nem
// cartões: esses modelos só saem por campanha. Lido da estrutura do modelo,
// nunca do texto.
// O servidor confere de novo no envio (Whatsapp::Templates::ConversationSendGuard).
import { levaProdutos } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/produtosNaCampanha';
import { tipoNaConversa } from 'dashboard/routes/dashboard/campaigns/modelos/conversa/modeloNaConversa';

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

const modeloComum = template =>
  !levaProdutos(template) &&
  !temTopoDeProduto(template) &&
  !temBotaoDeCatalogo(template) &&
  !temCarrossel(template);

// #1716: a escolha de modelo da CONVERSA sabe completar produto, vários
// produtos, carrossel de produtos e carrossel de fotos (`tipoNaConversa`).
// `completa` diz o que esta tela e esta pessoa conseguem completar:
//   { fotos: true }    — carrossel de fotos;
//   { produtos: true } — os de produto (flag whatsapp_campaign_products).
// Sem `completa` (nova conversa, CRM, avisos do agendamento), como antes.
export const vaiNaConversa = (template, { completa } = {}) => {
  if (modeloComum(template)) return true;
  const tipo = completa ? tipoNaConversa(template) : '';
  if (tipo === 'cartoes') return Boolean(completa.fotos);
  return Boolean(tipo) && Boolean(completa.produtos);
};
