# Reação do cliente no Instagram (#2113): como no app, vira o selo na mensagem reagida, gravado pelo mesmo
# Whatsapp::ReactionRecorder do WhatsApp (content_attributes.reactions, uma por autor, emoji vazio tira).
#
# Webhook da Meta (campo message_reactions), sem eco:
#   { sender:, recipient:, timestamp:, reaction: { mid:, action: 'react' | 'unreact', reaction: 'love', emoji: '❤️' } }
#   https://developers.facebook.com/docs/messenger-platform/instagram/features/webhook
# - 'react' traz o emoji; 'unreact' não traz: tira a reação do cliente.
# - 'react' só com o tipo ('reaction': love, like…) e sem 'emoji' (a doc marca os dois como opcionais): a doc não diz
#   que desenho cada tipo é, então não se grava emoji adivinhado; o descarte vai para o log (#2113, a confirmar em
#   conta real).
# - A mensagem reagida é achada pelo mid na caixa (o source_id das mensagens do Instagram); não achada, nada a fazer.
# - Vale para a caixa Instagram e para o Instagram ligado por página do Facebook, que chegam pelo mesmo
#   Webhooks::InstagramEventsJob. Só com a chave `conversa_instagram` da conta; desligada, a reação segue ignorada.
# - O caminho do agente da Autonomia (ReactionMaterializer) é outro e continua no job; um não derruba o outro.
class Instagram::ReacaoDoCliente
  FLAG = 'conversa_instagram'.freeze
  REAGIR = 'react'.freeze
  TIRAR = 'unreact'.freeze
  # A Meta manda o timestamp em milissegundos; acima disto (ano 5138 em segundos) não é segundo.
  LIMITE_EM_SEGUNDOS = 100_000_000_000

  def initialize(messaging:, inbox:)
    @messaging = messaging
    @inbox = inbox
    @dados = messaging[:reaction] || {}
  end

  # -> a mensagem reagida, ou nil.
  def perform
    return unless @inbox.account&.feature_enabled?(FLAG)
    return descartar if emoji.nil?

    Whatsapp::ReactionRecorder.new(inbox: @inbox, reacted_source_id: @dados[:mid], emoji: emoji, reacted_at: reagida_em).perform
  rescue StandardError => e
    Rails.logger.warn("[instagram][reaction] record failed inbox=#{@inbox.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
    nil
  end

  private

  def descartar
    Rails.logger.info("[instagram][reaction] discarded inbox=#{@inbox.id} action=#{@dados[:action]} type=#{@dados[:reaction]}")
    nil
  end

  # nil = não é reação que se grave: ação desconhecida ou 'react' sem emoji (nunca vira "tirar").
  def emoji
    case @dados[:action].to_s
    when REAGIR then @dados[:emoji].presence
    when TIRAR then ''
    end
  end

  def reagida_em
    valor = @messaging[:timestamp].to_i
    return if valor <= 0

    valor >= LIMITE_EM_SEGUNDOS ? Time.zone.at(valor / 1000.0) : Time.zone.at(valor)
  end
end
