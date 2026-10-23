# Reação (emoji) do cliente a uma mensagem do WhatsApp (#1702). Como no app, a reação não é balão novo: fica gravada
# na mensagem reagida, em `content_attributes.reactions`, e o painel desenha o selo embaixo dela.
#
#   content_attributes['reactions'] = [{ 'emoji' => '👍', 'sender_type' => 'Contact', 'sender_id' => 7, 'at' => '…' }]
#
# - Uma reação por autor: a nova substitui a anterior; emoji vazio (ou ausente, como a Cloud API manda) tira a dele.
# - Autor: o contato da conversa (reação recebida) ou, com `author:`, o atendente que reagiu pelo painel
#   (ConversaCanal::ReacaoDoAtendente). No WhatsApp o número da empresa tem UMA reação por mensagem: a de um atendente
#   substitui a de qualquer outro atendente ('User').
# - Só mexe na mensagem reagida (achada pelo source_id na caixa). Não cria mensagem, não reabre conversa, não notifica
#   e não conta para a janela de 24 h (que olha as mensagens recebidas). O painel atualiza pelo `message.updated`.
# - Mensagem reagida que não está no banco: nada a fazer (log info).
# - Reação tirada deixa uma lápide no Redis (autor + hora, por LAPIDE_VALIDADE): a reação mais antiga do mesmo autor
#   que chegar atrasada depois dela não volta. Fica fora de `reactions`, que continua só com as reações vivas.
# - Emoji com mais de MAXIMO_DE_BYTES é ignorado: um desenho só nunca passa disso.
# - A hora da reação recebida guarda a fração de segundo quando o provedor a manda (o Instagram manda em milissegundos,
#   #2113): sem ela, dois eventos do mesmo segundo entregues fora de ordem empatam e o mais antigo vence. O WhatsApp manda
#   em segundos e continua gravando sem fração.
# - Caixa híbrida (#1067): mensagem que saiu pelo WhatsApp API e ainda não recebeu o eco da Meta guarda o id físico no
#   source_id; o wamid da reação carrega esse mesmo id.
class Whatsapp::ReactionRecorder
  KEY = 'reactions'.freeze
  MAXIMO_DE_BYTES = 64
  # A Meta reentrega webhook por até 7 dias.
  LAPIDE_VALIDADE = 7.days
  CASAS_DA_FRACAO = 3

  def initialize(inbox:, reacted_source_id:, emoji:, reacted_at: nil, author: nil)
    @inbox = inbox
    @author = author
    @reacted_source_id = reacted_source_id.to_s
    @emoji = emoji.to_s.strip
    @reacted_at = reacted_at || Time.current
    @casas = reacted_at.respond_to?(:subsec) && reacted_at.subsec.nonzero? ? CASAS_DA_FRACAO : 0
  end

  # -> a mensagem reagida (atualizada ou não), ou nil quando ela não existe aqui.
  def perform
    return if @reacted_source_id.blank? || @emoji.bytesize > MAXIMO_DE_BYTES

    message = reacted_message
    return log_missing if message.nil?

    author = @author || message.conversation&.contact
    return if author.nil?

    message.with_lock { apply(message, author) }
    message
  end

  private

  def reacted_message
    scope = Message.where(inbox_id: @inbox.id).chat
    found = scope.find_by(source_id: @reacted_source_id)
    return found if found

    physical_id = WhatsappHybrid::Wamid.message_id(@reacted_source_id)
    scope.find_by(source_id: physical_id) if physical_id.present?
  end

  def apply(message, author)
    attrs = message.content_attributes.to_h
    current = Array(attrs[KEY]).select { |reaction| reaction.is_a?(Hash) }
    mine, others = current.partition { |reaction| author?(reaction, author) }
    return if stale?(message, author, mine)

    reactions = next_reactions(others, author)
    if reactions != current
      attrs = reactions.empty? ? attrs.except(KEY) : attrs.merge(KEY => reactions)
      ConversaCanal::GravarNaMensagem.atualizar!(message, content_attributes: attrs)
    end
    # A lápide só depois do banco: se a gravação falhar, nada fica dizendo que a reação foi tirada.
    remember_removal(message, author) if @emoji.empty?
  end

  def author?(reaction, author)
    return false unless reaction['sender_type'] == author.class.name
    return true if author.is_a?(User)

    reaction['sender_id'].to_i == author.id
  end

  # A Meta pode entregar fora de ordem: uma reação mais antiga não desfaz a mais nova do mesmo autor.
  def newer_than_this?(mine)
    mine.any? { |reaction| reaction['at'].present? && Time.zone.parse(reaction['at'].to_s) > @reacted_at }
  rescue ArgumentError
    false
  end

  def stale?(message, author, mine)
    newer_than_this?(mine) || removed_after_this?(message, author)
  end

  def next_reactions(others, author)
    @emoji.present? ? others + [entry_for(author)] : others
  end

  def removed_after_this?(message, author)
    removed_at = Redis::Alfred.get(tombstone_key(message, author))
    removed_at.present? && Time.zone.parse(removed_at) > @reacted_at
  rescue ArgumentError
    false
  end

  def remember_removal(message, author)
    Redis::Alfred.set(tombstone_key(message, author), @reacted_at.iso8601(@casas), ex: LAPIDE_VALIDADE.to_i)
  end

  # Atendente: uma reação do número da empresa, como em author?.
  def tombstone_key(message, author)
    who = author.is_a?(User) ? 'User' : "#{author.class.name}:#{author.id}"
    "whatsapp:reaction_removed:#{message.id}:#{who}"
  end

  def entry_for(author)
    { 'emoji' => @emoji, 'sender_type' => author.class.name, 'sender_id' => author.id, 'at' => @reacted_at.iso8601(@casas) }
  end

  def log_missing
    Rails.logger.info("[whatsapp][reaction] reacted message not found inbox=#{@inbox.id}")
    nil
  end
end
