# "Lido" do e-mail no servidor do cliente (#1870) fora do request: abrir ou marcar não lida no painel não espera o IMAP.
# Fila low. Um job por CAIXA (ConversaCanal::FilaDoEmailLido): os pedidos das conversas da caixa juntam numa fila e o job
# escreve todos numa conexão só, com o lock da caixa, renovado a cada conversa. O serviço relê o estado de cada conversa
# na hora (vale o último: abriu de novo depois do "não lida", fica lida).
# - Caixa ocupada pela importação (ela segura o lock até 5 min): o job volta a tentar a cada ESPERA_DO_LOCK, até
#   TETO_DA_ESPERA desde o INÍCIO DA ESPERA (a primeira vez que achou a caixa ocupada; o relógio segue nos reagendamentos
#   por lock perdido, então a espera de uma rodada inteira tem teto). Esgotou: desiste.
# - Lock perdido no meio (passou do TTL e a importação pegou): volta depois com o que falta, até PERDAS_DO_LOCK vezes.
# - Rede, timeout, BYE, NO/BAD fora da autenticação, OAuth 5xx, Redis fora, deadlock ou pool do banco esgotado: tenta
#   de novo, pouco (TENTATIVAS); os pedidos não
#   escritos voltam para a fila. Esgotou: desiste. A nova tentativa do retry_on não passa pelo `agendar?`: o job é
#   idempotente (os pedidos saem da fila de forma atômica; um segundo job da caixa acha a fila vazia ou espera o lock).
# - Credencial recusada (caixa a reautorizar, token OAuth vazio, refresh_token ausente, NO/BAD no LOGIN ou AUTHENTICATE,
#   mecanismo inválido, OAuth 4xx): não tenta de novo, para não bloquear a conta no Gmail/Outlook. Desiste.
# - Erro inesperado numa conversa (pedido envenenado): registra, descarta aquele pedido e segue o lote.
# Desistir nunca é silencioso: log com a classe e rastreio (só a primeira falha por caixa na hora,
# ConversaCanal::FalhaDoEmailLido). Desistir esvazia a fila e solta as marcas de "não lida pendente".
class ConversaCanal::EmailLidoNoServidorJob < ApplicationJob
  queue_as :low

  ESPERA = 3.seconds
  ESPERA_DO_LOCK = 20.seconds
  TETO_DA_ESPERA = 10.minutes
  PERDAS_DO_LOCK = 3
  TENTATIVAS = 3
  # Conversas por conexão: com o lock renovado a cada uma, a seção crítica tem teto conhecido; o resto vai num job novo.
  POR_JOB = 10
  NAO_LIDA = 'nao_lida'.freeze
  LIDO = 'lido'.freeze
  TRANSITORIOS = [IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Timeout::Error, Net::IMAP::Error,
                  OAuth2::Error, Faraday::Error, Redis::BaseError, ActiveRecord::ConnectionTimeoutError,
                  ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::ConnectionNotEstablished,
                  PG::ConnectionBad].freeze

  retry_on(*TRANSITORIOS, wait: 10.seconds, attempts: TENTATIVAS) do |job, error|
    job.desistir(error)
  end

  discard_on(ConversaCanal::ConexaoDoEmail::CredencialRecusada) do |job, error|
    job.desistir(error)
  end

  def self.agendar(conversation, acao)
    ConversaCanal::FilaDoEmailLido.new(conversation.inbox_id).adicionar(conversation.id, acao)
    agendar_se_pendente(conversation.inbox)
  end

  def self.agendar_se_pendente(inbox, *args)
    fila = ConversaCanal::FilaDoEmailLido.new(inbox.id)
    return unless fila.pendente? && fila.agendar?(TETO_DA_ESPERA + 1.minute)

    set(wait: args.empty? ? ESPERA : ESPERA_DO_LOCK).perform_later(inbox, *args)
  end

  # espera_desde: início da espera pela caixa (epoch), nil enquanto não esperou. perdas: vezes que perdeu o lock.
  def perform(inbox, espera_desde = nil, perdas = 0)
    @inbox = inbox
    @espera_desde = espera_desde
    @perdas = perdas
    return desistir_sem_registro unless ConversaCanal::EmailLido.ligado?(inbox)
    return fila.soltar_agendamento unless fila.pendente?

    renovar_nao_lidas

    escrever_pedidos
    self.class.agendar_se_pendente(inbox)
  rescue ConversaCanal::LockDaCaixa::LockPerdido => e
    voltar_depois_da_perda(e)
  rescue MutexApplicationJob::LockAcquisitionError => e
    esperar_ou_desistir(e)
  end

  # Público: os blocos de retry_on/discard_on desistem por ele. A fila e o agendamento saem juntos (MULTI); o que entrar
  # depois disso agenda o próprio job, e o que já estiver lá é reagendado aqui. As marcas de "não lida pendente" dos
  # pedidos tirados saem: o estado fica o que está gravado (a importação volta a ver as passagens).
  def desistir(error)
    inbox = arguments.first
    soltar_nao_lidas(inbox, ConversaCanal::FilaDoEmailLido.new(inbox.id).esvaziar)
    registrar(error, inbox, "painel -> servidor inbox=#{inbox.id}")
    self.class.agendar_se_pendente(inbox)
  end

  private

  def fila
    @fila ||= ConversaCanal::FilaDoEmailLido.new(@inbox.id)
  end

  def escrever_pedidos
    ConversaCanal::ConexaoDoEmail.abrir(@inbox.channel) do |imap, lock|
      fila.soltar_agendamento
      escrever_lote(imap, lock, fila.retirar(POR_JOB))
    end
  end

  # O pedido sai da fila antes de escrever; o que não foi escrito (rede, lock perdido) volta para ela.
  def escrever_lote(imap, lock, pedidos)
    feitos = 0
    pedidos.each do |acao, conversation_id|
      escrever(imap, acao, conversation_id)
      feitos += 1
      lock.renovar!
    end
  ensure
    devolver(pedidos.drop(feitos))
  end

  # Limitação aceita: com o Redis fora aqui, o que não foi escrito se perde (o Sidekiq também para). O painel continua
  # certo; só aquela leitura não chega ao servidor. Não some calado: log de erro com a classe, e o erro segue.
  def devolver(pedidos)
    fila.devolver(pedidos)
  rescue StandardError => e
    Rails.logger.error("[conversa_canal][email_lido] devolver pedidos falhou inbox=#{@inbox.id} #{e.class}")
    raise
  end

  def escrever(imap, acao, conversation_id)
    conversation = @inbox.conversations.find_by(id: conversation_id)
    return if conversation.nil?

    servico = ConversaCanal::EmailLidoNoServidor.new(conversation: conversation)
    acao == NAO_LIDA ? servico.marcar_nao_lida(imap) : servico.marcar_lido(imap)
  rescue ConversaCanal::LockDaCaixa::LockPerdido, *TRANSITORIOS
    raise
  rescue StandardError => e
    descartar(e, acao, conversation_id)
  end

  # Pedido envenenado: não trava a caixa. Sai da fila (já saiu, em `retirar`), solta a marca e segue o lote. Nada daqui
  # estoura: um erro aqui faria o pedido voltar pelo `ensure` do lote.
  def descartar(error, acao, conversation_id)
    soltar_nao_lidas(@inbox, [[acao, conversation_id]])
    registrar(error, @inbox, "painel -> servidor inbox=#{@inbox.id} conversation=#{conversation_id}")
  rescue StandardError => e
    Rails.logger.error("[conversa_canal][email_lido] descartar pedido falhou inbox=#{@inbox.id} #{e.class}")
  end

  def voltar_depois_da_perda(error)
    perdas = @perdas + 1
    return desistir(error) if perdas > PERDAS_DO_LOCK

    self.class.agendar_se_pendente(@inbox, @espera_desde || Time.current.to_i, perdas)
  end

  # Aqui o job ainda segura o agendamento (não chegou a abrir a conexão): reagenda direto.
  def esperar_ou_desistir(error)
    espera_desde = @espera_desde || Time.current.to_i
    return desistir(error) if Time.current.to_i - espera_desde >= TETO_DA_ESPERA.to_i

    self.class.set(wait: ESPERA_DO_LOCK).perform_later(@inbox, espera_desde, @perdas)
  end

  # Cada execução renova a marca de "não lida pendente" dos pedidos de "não lida" ainda na fila (validade de
  # ConversaCanal::EmailLido::NAO_LIDA_PENDENTE a partir daqui): vale a cadeia inteira de reagendamentos (espera pela
  # caixa, lock perdido, nova tentativa do retry_on) até a escrita ou a desistência.
  # Falha aqui registra e segue: a escrita do lote ainda vale.
  def renovar_nao_lidas
    ultimas_recebidas(@inbox, fila.pedidos).each { |ultima| ConversaCanal::EmailLido.nao_lida_pendente!(ultima) }
  rescue StandardError => e
    registrar(e, @inbox, "renovar não lidas inbox=#{@inbox.id}")
  end

  def desistir_sem_registro
    soltar_nao_lidas(@inbox, fila.esvaziar)
  end

  def registrar(error, inbox, onde)
    ConversaCanal::FalhaDoEmailLido.registrar(error, account: inbox.account, inbox_id: inbox.id, onde: onde)
  end

  def soltar_nao_lidas(inbox, pedidos)
    ultimas_recebidas(inbox, pedidos).each { |ultima| ConversaCanal::EmailLido.nao_lida_resolvida!(ultima.id) }
  end

  # A última recebida de cada conversa dos pedidos de "não lida", numa query. É o mesmo `messages.incoming.last` do
  # unread: o default_scope do Message ordena por created_at.
  def ultimas_recebidas(inbox, pedidos)
    ids = pedidos.filter_map { |acao, conversation_id| conversation_id if acao == NAO_LIDA }
    return [] if ids.empty?

    Message.incoming.where(inbox_id: inbox.id, conversation_id: ids)
           .select('DISTINCT ON (messages.conversation_id) messages.*')
           .reorder(:conversation_id, created_at: :desc, id: :desc).to_a
  end
end
