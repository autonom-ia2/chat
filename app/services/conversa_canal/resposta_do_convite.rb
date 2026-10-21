# Resposta ao convite de reunião pela caixa de e-mail (#1984): Sim (aceito), Talvez ou Não (recusado).
# O caminho depende da caixa:
# - Microsoft com a agenda ligada: responde no evento da própria agenda pelo Graph (o Outlook já pôs o convite lá);
# - Google com a agenda ligada: responde no evento da agenda (achado pelo UID do convite);
# - nos dois, o evento só vale se for do mesmo organizador do convite (um convite forjado com o UID de uma reunião
#   real não responde por ela); sem evento assim, cai na resposta por e-mail;
# - as demais (Hostinger e IMAP/SMTP): e-mail de resposta padrão de calendário (iMIP, RFC 6047) ao organizador.
# Só responde a caixa que está entre os convidados; convite cancelado ou de outra forma não se responde.
# A resposta fica gravada no próprio convite da mensagem (minha_resposta), para todos da equipe verem.
class ConversaCanal::RespostaDoConvite
  RESPOSTAS = %w[aceito talvez recusado].freeze
  CHAVE = 'convite_da_reuniao'.freeze
  Recusa = Class.new(StandardError)
  # O provedor da agenda ou o servidor de e-mail falhou: a resposta não foi entregue.
  FalhaNoEnvio = Class.new(StandardError)

  def initialize(message:, resposta:, user:)
    @message = message
    @resposta = resposta.to_s
    @user = user
  end

  def perform
    validar!
    # A mesma resposta de novo não sai outra vez: cada troca é um e-mail ou aviso ao organizador.
    return convite if convite['minha_resposta'] == @resposta

    via = responder
    gravar(via)
  end

  private

  def convite
    @convite ||= (@message.content_attributes || {}).dig('email', 'convite') || {}
  end

  def channel
    @channel ||= @message.inbox.channel
  end

  def validar!
    recusar(:sem_chave) unless @message.account.feature_enabled?(CHAVE)
    recusar(:resposta_invalida) unless RESPOSTAS.include?(@resposta)
    recusar(:sem_convite) unless convite_aberto?
    recusar(:nao_e_email) unless channel.is_a?(Channel::Email)
    recusar(:nao_convidada) unless convidada?
    recusar(:ja_passou) if ja_passou?
  end

  # Reunião única que já terminou não se responde. A série (RRULE) segue valendo depois da primeira.
  def ja_passou?
    termino = convite['fim'] || convite['inicio']
    convite['recorrente'].blank? && termino.present? && termino.to_i < Time.current.to_i
  end

  # Convite recebido, ainda de pé (cancelamento não se responde) e com o UID que o organizador reconhece.
  def convite_aberto?
    @message.incoming? && convite['metodo'] == 'REQUEST' && convite['uid'].present? && convite.dig('organizador', 'email').present?
  end

  def convidada?
    endereco.present?
  end

  # O endereço da caixa na lista de convidados: o e-mail da caixa ou o da agenda ligada a ela.
  def endereco
    @endereco ||= begin
      meus = [channel.email, channel.try(:calendar_identity)].compact_blank.map(&:downcase)
      Array(convite['convidados']).map { |pessoa| pessoa['email'].to_s.downcase }.find { |email| meus.include?(email) }
    end
  end

  # -> 'agenda', 'agenda_sem_aviso' (o organizador não pede respostas: marcou só na agenda da caixa) ou 'email'.
  def responder
    agenda = pela_agenda?
    return 'agenda_sem_aviso' if agenda == :sem_aviso
    return 'agenda' if agenda

    PorEmail.new(channel: channel, convite: convite, resposta: @resposta, endereco: endereco).perform
    'email'
  rescue Recusa, FalhaNoEnvio
    raise
  rescue StandardError => e
    # Token revogado, rede fora, resposta ilegível do provedor: a resposta não saiu.
    Rails.logger.warn("[RespostaDoConvite] mensagem #{@message.id}: #{e.class} #{e.backtrace&.first}")
    raise FalhaNoEnvio, e.class.name
  end

  # -> true (ou :sem_aviso) quando a agenda respondeu; false quando a resposta vai por e-mail.
  # Ocorrência de uma série no Google: a busca pelo UID devolve a série inteira; vai por e-mail, com o RECURRENCE-ID,
  # e o organizador marca só aquela ocorrência.
  def pela_agenda?
    if agenda?(:microsoft?)
      AgendaMicrosoft.new(channel: channel, message: @message, convite: convite, resposta: @resposta).perform
    elsif agenda?(:google?) && convite['ocorrencia'].blank?
      AgendaGoogle.new(channel: channel, convite: convite, resposta: @resposta).perform
    else
      false
    end
  end

  # Agenda ligada na caixa: a mesma condição do CRM (Crm::Meetings::Creator), que pede o token com escopo de agenda.
  def agenda?(provedor)
    channel.public_send(provedor) && channel.calendar_enabled?
  end

  # Grava sobre a versão atual da mensagem (with_lock relê a linha): outra escrita nela durante a resposta, que pode
  # levar segundos, não se perde.
  def gravar(via)
    @message.with_lock do
      atributos = (@message.content_attributes || {}).deep_dup
      atributos['email']['convite'] = atributos['email']['convite'].merge(
        'minha_resposta' => @resposta, 'respondida_em' => Time.current.to_i, 'respondida_por' => @user&.id, 'via' => via
      )
      @message.update!(content_attributes: atributos)
      atributos['email']['convite']
    end
  end

  def recusar(motivo)
    raise Recusa, I18n.t("conversa_canal.convite.#{motivo}")
  end
end
