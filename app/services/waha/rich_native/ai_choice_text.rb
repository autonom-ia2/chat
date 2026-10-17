# O voto e a resposta ao convite como o contexto da IA os lê (chat#1709, rodada de correção, itens 14 e 15). O `content`
# do turno leva só a escolha ("Votou: Não", Waha::RichNative::AiTurn); aqui volta o texto completo, com a pergunta
# guardada em `c2y_ai_turn.question`, e a escolha que o cliente retirou ou trocou depois ganha a marca de que não vale
# mais (Waha::RichNative::TurnKinds.choice_current?, contrato público). Mensagem que não é escolha: nil (fica como está).
# Quem usa: a resposta do agente (Waha::RichNative::ResponderChoice) e, por prepend (Waha::RichNative::AiChoiceContext),
# a IA do CRM (Crm::Ai::ContextBuilder), a do assunto e os Decisores (Autonomia::Decisores::Estado), o classificador de
# opt-out (Crm::Ai::OptOutClassifier, que decide com o texto completo) e o copiloto do atendente.
module Waha::RichNative::AiChoiceText
  STALE_KEY = 'waha.ai.choice_no_longer_valid'.freeze

  # A mensagem com o `content` trocado pelo texto completo, sem gravar nada; a própria mensagem quando não é escolha.
  class WithText < SimpleDelegator
    def initialize(message, text)
      super(message)
      @text = text
    end

    def content
      @text
    end
  end

  module_function

  # A mensagem é o turno de uma escolha (marca estruturada `c2y_ai_turn`, gravada só pelo chat2you).
  def choice?(message)
    message&.content_attributes.to_h[Waha::RichNative::AiTurn::CHOICE_KEY].is_a?(Hash)
  end

  def for(message)
    return unless choice?(message)

    choice = message.content_attributes.to_h[Waha::RichNative::AiTurn::CHOICE_KEY]

    text = Waha::RichNative::AiTurn.full_text(message.account, choice)
    return text if Waha::RichNative::TurnKinds.choice_current?(message)

    "#{text} #{Waha::RichNative::AiTurn.translate(message.account, STALE_KEY)}"
  end

  def wrap(message)
    text = self.for(message)
    text ? WithText.new(message, text) : message
  end
end
