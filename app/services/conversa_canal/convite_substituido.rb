# Convite que ficou para trás (#1995): o organizador mudou a reunião (SEQUENCE maior) ou cancelou (CANCEL), num e-mail
# mais novo. O cartão do convite antigo não pode seguir perguntando "Vai participar?": a resposta iria para uma versão
# que não vale mais. Aqui o convite antigo ganha `substituido_por` (a mensagem da versão vigente),
# `substituido_cancelado` e `substituido_na_conversa` (onde está a versão nova); o cartão troca a pergunta por um aviso
# e a resposta (RespostaDoConvite) recusa.
# - Mesma reunião: mesmo UID e mesmo organizador, do mesmo remetente e na mesma caixa, em qualquer conversa (o Outlook
#   manda a atualização num e-mail novo). Olha só o último ano.
# - Substitui quem tem SEQUENCE maior. Na mesma SEQUENCE, só a troca de método (CANCEL depois do REQUEST, ou o REQUEST
#   que readiciona a caixa depois do CANCEL), pelo DTSTAMP; o mesmo convite reenviado (só um convidado a mais) não
#   substitui, e a resposta já dada continua valendo.
# - Ocorrência (RECURRENCE-ID) só é substituída pela mesma ocorrência ou pela série inteira; a série não é substituída
#   pela mudança de uma ocorrência só.
# - Vale também fora de ordem (o convite antigo que chega depois do novo já nasce substituído) e com dois e-mails
#   chegando juntos: a marca só troca para uma versão mais nova que a já marcada.
class ConversaCanal::ConviteSubstituido
  JANELA = 1.year

  def self.marcar(message)
    new(message).perform
  end

  def initialize(message)
    @message = message
  end

  def perform
    return if uid.blank?

    reuniao = mesma_reuniao
    reuniao.each do |antiga|
      vigente = vigente_para(antiga, reuniao)
      marcar(antiga, vigente) if vigente
    end
  end

  private

  def uid
    convite(@message)['uid']
  end

  def convite(message)
    (message.content_attributes || {}).deep_stringify_keys.dig('email', 'convite') || {}
  end

  # O UID filtra no banco pelo texto de content_attributes, sem aspas: em produção o JSON vem guardado como texto, com
  # as aspas escapadas (um UID com aspas ou barra invertida não casa, e o convite antigo fica como está). A conferência
  # campo a campo vem depois, aqui. Roda num job da fila low: o volume é o do remetente nessa caixa, num ano.
  def mesma_reuniao
    Message.incoming
           .where(inbox_id: @message.inbox_id, sender_type: @message.sender_type, sender_id: @message.sender_id)
           .where(created_at: JANELA.ago..)
           .where('messages.content_attributes::text LIKE ?', "%#{Message.sanitize_sql_like(uid)}%")
           .to_a
           .select { |message| mesma_reuniao?(convite(message)) }
  end

  # A versão que vale hoje para o convite antigo, seguindo a fila de substituições: REQUEST, depois CANCEL, depois o
  # REQUEST que readicionou a caixa apontam todos para o último, que não está cancelado.
  def vigente_para(antiga, reuniao)
    vigente = nil
    atual = antiga
    while (proxima = reuniao.select { |outra| substitui?(outra, atual) }.max_by { |outra| ordem(outra) })
      vigente = atual = proxima
    end
    vigente
  end

  def mesma_reuniao?(dados)
    dados['uid'] == uid && dados.dig('organizador', 'email') == convite(@message).dig('organizador', 'email')
  end

  def substitui?(nova, antiga)
    return false if nova.id == antiga.id

    dados_nova = convite(nova)
    dados_antiga = convite(antiga)
    return false unless dados_nova['ocorrencia'].nil? || dados_nova['ocorrencia'] == dados_antiga['ocorrencia']
    return dados_nova['sequencia'].to_i > dados_antiga['sequencia'].to_i if dados_nova['sequencia'].to_i != dados_antiga['sequencia'].to_i

    dados_nova['metodo'] != dados_antiga['metodo'] && (ordem(nova) <=> ordem(antiga)) == 1
  end

  def ordem(message)
    dados = convite(message)
    [dados['sequencia'].to_i, dados['carimbo'].to_i, message.id]
  end

  # Sem a validação do Message (o limite de mensagens por minuto da conversa barraria a marca numa rajada); o update
  # avisa a tela pelo evento de mensagem atualizada.
  def marcar(antiga, vigente)
    antiga.with_lock do
      atributos = (antiga.content_attributes || {}).deep_stringify_keys
      dados = atributos.dig('email', 'convite')
      next if dados.nil? || !mais_nova_que_a_marcada?(vigente, dados['substituido_por'])

      dados['substituido_por'] = vigente.id
      dados['substituido_cancelado'] = convite(vigente)['metodo'] == 'CANCEL'
      dados['substituido_na_conversa'] = vigente.conversation.display_id
      antiga.content_attributes = atributos
      antiga.save!(validate: false)
    end
  end

  def mais_nova_que_a_marcada?(vigente, marcada_id)
    return true if marcada_id.blank?

    marcada = Message.find_by(id: marcada_id)
    marcada.nil? || (ordem(vigente) <=> ordem(marcada)) == 1
  end
end
