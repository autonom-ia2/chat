# Prepends nos leitores de conversa das IAs do CRM (chat#1709, rodada de correção, itens 14 e 15), em arquivo próprio
# para não editar os do Multifunnel: o voto e a resposta ao convite entram com a pergunta, e a escolha que não vale mais
# vem marcada (Waha::RichNative::AiChoiceText). Mensagem que não é escolha passa igual.
module Waha::RichNative::AiChoiceContext
  # Em Crm::Ai::ContextBuilder (avaliação do card, follow-up).
  module ContextBuilder
    private

    def message_content(message)
      Waha::RichNative::AiChoiceText.for(message) || super
    end
  end

  # Em Autonomia::Decisores::Estado (as mensagens que o Crm::Subjects::Identifier e os decisores leem).
  module Estado
    private

    def textos(lista, com_autor: false)
      super(Array(lista).map { |mensagem| Waha::RichNative::AiChoiceText.wrap(mensagem) }, com_autor: com_autor)
    end
  end
end
