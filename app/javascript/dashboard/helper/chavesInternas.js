// #3176 — as chaves de custom_attributes que são do sistema, e não da equipe:
// as da WAHA (o chat id, o jid e o lid com que ela acha a conversa do contato)
// e as de controle da Prospecção (o lead, o fornecedor, o código do lugar, quem
// converteu, as marcas do nome e do cargo). Não aparecem em tela nenhuma.
//
// A lista é do servidor (app/services/relationships/chaves_internas.rb) e chega
// na resposta da conta (`chaves_internas`); o painel não tem cópia. Quem lê é o
// getter `attributes/getChavesInternas` (da conta aberta), e quem esconde são as
// fontes de definições do painel: os getters de store/modules/attributes.js, o
// estado de composables/useRelationships.js e os campos soltos da ficha
// (relacionamentos/ficha/atributos.js). Enquanto a conta não chegou a lista é
// vazia e nada a mais é escondido; o getter recalcula quando ela chega.
//
// As definições continuam no servidor e no store, e os valores não são tocados
// (o servidor mescla custom_attributes ao gravar): a WAHA e a Prospecção
// dependem deles para achar o contato. Comparação pela chave inteira.
export const chavesInternasDaConta = conta =>
  Array.isArray(conta?.chaves_internas) ? conta.chaves_internas : [];

export const ehChaveInterna = (chave, chaves = []) =>
  (chaves ?? []).includes(chave);

// As definições sem as das chaves internas, na mesma ordem. Aceita a definição
// como vem da API (attribute_key) ou já em camelCase (attributeKey), como sai do
// getter attributes/getContactAttributes.
export const semChavesInternas = (definicoes = [], chaves = []) =>
  definicoes.filter(
    definicao =>
      !ehChaveInterna(
        definicao?.attribute_key ?? definicao?.attributeKey,
        chaves
      )
  );
