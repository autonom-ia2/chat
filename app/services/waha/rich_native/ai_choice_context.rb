# Prepends nos leitores de conversa das IAs (chat#1709, rodada de correção, itens 14 e 15, e revisão), em arquivo
# próprio para não editar os do Multifunnel e do Copiloto: o voto e a resposta ao convite entram com a pergunta, e a
# escolha que não vale mais vem marcada (Waha::RichNative::AiChoiceText). Mensagem que não é escolha passa igual.
module Waha::RichNative::AiChoiceContext
  # Em Crm::Ai::ContextBuilder (avaliação do card, follow-up).
  module ContextBuilder
    private

    def message_content(message)
      Waha::RichNative::AiChoiceText.for(message) || super
    end
  end

  # Em Autonomia::Decisores::Estado (o Crm::Subjects::Identifier e os Decisores das automações): as mensagens lidas e a
  # última mensagem (a leitura `ultima_mensagem` do Decisor).
  module Estado
    private

    def textos(lista, com_autor: false)
      super(Array(lista).map { |mensagem| Waha::RichNative::AiChoiceText.wrap(mensagem) }, com_autor: com_autor)
    end

    def ler_ultima_mensagem
      lida = super
      mensagem = message || conversation&.messages&.incoming&.reorder(id: :desc)&.first
      texto = Waha::RichNative::AiChoiceText.for(mensagem)
      texto ? lida.merge(last_message: texto.strip.first(self.class::MAX_CARACTERES)) : lida
    end
  end

  # Em Crm::Ai::OptOutClassifier (follow-up de IA e campanha do WhatsApp): voto numa enquete ou resposta a um convite não
  # é pedido para parar, mesmo quando a escolha é "Não". A escolha é reconhecida pela marca estruturada `c2y_ai_turn`
  # (nunca pelo texto), e o modelo nem é perguntado.
  module OptOut
    def perform
      return { decision: 'nao', motivo: 'resposta_ao_assunto' } if Waha::RichNative::AiChoiceText.choice?(@message)

      super
    end
  end

  # Em Autonomia::Copilot::ConversationCopilot e ConversationChat (o copiloto do atendente): a conversa lida pelo modelo.
  module Copilot
    private

    def chat_messages
      return @c2y_chat_messages if @c2y_chat_messages

      @c2y_chat_messages = super.map { |message| Waha::RichNative::AiChoiceText.wrap(message) }
    end
  end
end
