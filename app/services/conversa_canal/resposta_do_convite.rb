# Resposta ao convite de reunião pela caixa de e-mail (#1984): Sim (aceito), Talvez ou Não (recusado).
# O caminho depende da caixa:
# - Microsoft com a agenda ligada: responde no evento da própria agenda pelo Graph (o Outlook já pôs o convite lá);
# - Google com a agenda ligada: responde no evento da agenda (achado pelo UID do convite);
# - nos dois, o evento só vale se for do mesmo organizador do convite (um convite forjado com o UID de uma reunião
#   real não responde por ela); sem evento assim, cai na resposta por e-mail;
# - as demais (Hostinger e IMAP/SMTP): e-mail de resposta padrão de calendário (iMIP, RFC 6047) ao organizador.
# Só responde a caixa que está entre os convidados; convite cancelado ou de outra forma não se responde, nem o que
# ficou para trás numa versão mais nova (ConversaCanal::ConviteSubstituido, #1995).
# A resposta fica gravada no próprio convite da mensagem (minha_resposta), para todos da equipe verem.
# Uma resposta por vez em cada convite (trava no Redis, #1995): o clique de outra pessoa enquanto a primeira resposta
# sai é recusado (em_andamento); quem clica depois relê a mensagem e não manda de novo a resposta que já saiu.
class ConversaCanal::RespostaDoConvite
  RESPOSTAS = %w[aceito talvez recusado].freeze
  CHAVE = 'convite_da_reuniao'.freeze
  Recusa = Class.new(StandardError)
  # O provedor da agenda ou o servidor de e-mail falhou: a resposta não foi entregue.
  FalhaNoEnvio = Class.new(StandardError)
  # Bem maior que a requisição: o Rack::Timeout corta o clique antes (15 s, o padrão, sem RACK_TIMEOUT_SERVICE_TIMEOUT
  # em produção) e o ensure solta a trava. Ela só vence sozinha se o processo morrer no meio.
  TEMPO_DA_TRAVA = 90.seconds
  CHAVE_DA_TRAVA = 'CONVERSA_CANAL::CONVITE_RESPOSTA::%<message_id>d'.freeze

  def initialize(message:, resposta:, user:)
    @message = message
    @resposta = resposta.to_s
    @user = user
  end

  def perform
    travar do
      reler
      validar!
      # A mesma resposta de novo não sai outra vez: cada troca é um e-mail ou aviso ao organizador.
      next convite if convite['minha_resposta'] == @resposta

      gravar(responder)
    end
  end

  private

  def convite
    @convite ||= (@message.content_attributes || {}).dig('email', 'convite') || {}
  end

  def travar
    travas = Redis::LockManager.new
    chave = format(CHAVE_DA_TRAVA, message_id: @message.id)
    recusar(:em_andamento) unless trava_livre?(travas, chave)
    begin
      yield
    ensure
      soltar(travas, chave)
    end
  end

  # Redis caindo depois da resposta não troca o resultado: a trava vence sozinha no TEMPO_DA_TRAVA.
  def soltar(travas, chave)
    travas.unlock(chave)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    Rails.logger.warn("[RespostaDoConvite] trava não solta na mensagem #{@message.id}: #{e.class}")
  end

  # Redis fora do ar: a resposta não sai (502 com a frase da tela), em vez de um erro 500.
  def trava_livre?(travas, chave)
    travas.lock(chave, TEMPO_DA_TRAVA)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    Rails.logger.warn("[RespostaDoConvite] trava indisponível na mensagem #{@message.id}: #{e.class}")
    raise FalhaNoEnvio, e.class.name
  end

  # A mensagem como está agora: outra pessoa pode ter respondido entre a tela abrir e este clique.
  def reler
    @message.reload
    @convite = nil
    @endereco = nil
  end

  def channel
    @channel ||= @message.inbox.channel
  end

  def validar!
    recusar(:sem_chave) unless @message.account.feature_enabled?(CHAVE)
    recusar(:resposta_invalida) unless RESPOSTAS.include?(@resposta)
    validar_convite!
    recusar(:nao_e_email) unless channel.is_a?(Channel::Email)
    recusar(:nao_convidada) unless convidada?
  end

  def validar_convite!
    recusar(:sem_convite) unless convite_aberto?
    recusar(:substituido) if convite['substituido_por'].present?
    recusar(:ja_passou) if ja_passou?
  end

  # Reunião que já terminou não se responde. A série (RRULE) vale até o fim da última ocorrência (fim_da_serie, quando
  # tem UNTIL ou COUNT); sem fim, segue respondível.
  def ja_passou?
    termino = convite['recorrente'].present? ? convite['fim_da_serie'] : convite['fim'] || convite['inicio']
    termino.present? && termino.to_i < Time.current.to_i
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
