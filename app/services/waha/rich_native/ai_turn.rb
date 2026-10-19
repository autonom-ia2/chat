# O voto numa enquete nativa e a resposta a um convite de evento nativo como TURNO DO CLIENTE para o agente de IA
# (chat#1709, aprovado pelo Rodrigo em 16/10/2026). Com a flag, quando o voto (ou a resposta) é novo e escolhe algo, a
# mensagem criada para ele continua RECEBIDA (do contato), marcada `c2y_hidden`: a tela mostra o voto agregado na
# enquete (ou no evento) e esconde esta mensagem. Por ser recebida, ela segue o caminho normal de qualquer mensagem do
# cliente (Autonomia::Agents::Operate::MessageListener: debounce, posse do turno do #1627, espera do assunto); dentro
# do debounce, o voto trocado responde só à última escolha.
# O `content` leva SÓ a escolha, com o mínimo de contexto ("Votou: Não"; "Respondeu ao convite: Vou"), no idioma da
# conta: com a pergunta inteira no texto, uma automação "contém cancelar" dispararia num "Não" à pergunta "Quer
# cancelar?". A pergunta (ou o nome do evento) fica em `content_attributes.c2y_ai_turn.question`, e quem monta o
# contexto da IA lê o texto completo por Waha::RichNative::AiChoiceText (a resposta do agente, a IA do CRM e a do
# assunto), que também marca a escolha que não vale mais.
# Voto retirado (sem opção) ou antigo (um job refeito, que não troca a escolha atual): continua atividade escondida,
# sem turno para a IA. Sem a flag, nada aqui roda (Waha::RichNative::Inbound#apply_without_flag, como na main).
module Waha::RichNative::AiTurn
  # A escolha do turno ({ kind, target_id, choice, question }), para o settle conferir se ela ainda vale
  # (Waha::RichNative::TurnKinds.choice_current?). Chave interna: a API não a forja (Waha::RichNative::ContractGuard).
  CHOICE_KEY = 'c2y_ai_turn'.freeze

  module_function

  def choice(kind, target, value)
    { CHOICE_KEY => { 'kind' => kind, 'target_id' => target.id, 'choice' => value, 'question' => excerpt(target.content) } }
  end

  # O `content` do turno: só a escolha.
  def poll_text(account, _poll, titles)
    translate(account, 'waha.ai.poll_vote_choice', options: titles.join(', '))
  end

  def event_text(account, _event, response)
    translate(account, 'waha.ai.event_response_choice', response: event_answer(account, response))
  end

  # O texto completo, com a pergunta, para o contexto da IA (Waha::RichNative::AiChoiceText).
  def full_text(account, choice)
    question = choice['question'].to_s
    if choice['kind'] == 'event_response'
      return translate(account, 'waha.ai.event_response', name: question, response: event_answer(account, choice['choice']))
    end

    translate(account, 'waha.ai.poll_vote', question: question, options: Array(choice['choice']).join(', '))
  end

  def event_answer(account, response)
    translate(account, "waha.ai.event_answers.#{response}")
  end

  # A mensagem (ainda não gravada) vira o turno do cliente: recebida, pública, com o texto claro e escondida na tela.
  def record!(message, text, extra = {})
    message.message_type = :incoming
    message.private = false
    message.content = text
    message.content_attributes = message.content_attributes.to_h.merge(Waha::RichNative::Inbound::HIDDEN_KEY => true).merge(extra)
  end

  # Mensagem do cliente que é este turno (recebida e escondida da tela).
  def turn?(message)
    message.incoming? && message.content_attributes.to_h[Waha::RichNative::Inbound::HIDDEN_KEY] == true
  end

  def excerpt(text)
    text.to_s.strip.tr("\n", ' ').first(255)
  end

  # No idioma da conta; sem a chave nele (só há en e pt_BR), no idioma padrão.
  def translate(account, key, **)
    I18n.t(key, **, locale: account.locale, default: I18n.t(key, **))
  end
end
