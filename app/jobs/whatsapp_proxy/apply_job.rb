# Aplica no motor o proxy atribuído a uma sessão (#1516), agendado pela reconciliação ou pela atualização da aba do
# Híbrido. Recebe só o nome da sessão: a credencial vem de novo da API aqui dentro, para nunca passar pela fila (Redis).
# - Um por sessão de cada vez (WhatsappProxy::SessionLock: token único, compare-and-delete; a rake de migrar usa a
#   mesma trava).
# - Atribuição em recuo (troca desfeita há pouco): sai sem fazer nada — inclusive um job repetido que já estava na fila.
# - Antes do PUT confere o motor: proxy (host:porta) e credencial já iguais → só registra, sem PUT e sem zerar o recuo.
# - Troca desfeita: a atribuição volta inteira ao estado anterior (ou pendente) e entra em recuo (10 min a 24 h);
#   alerta `troca_desfeita` na primeira falha e no recuo máximo. Volta que falhou (alerta `volta_falhou` já saiu): o
#   motor é relido e a tabela fica igual ao que ele mostra; ilegível, fica sem credencial para a convergência resolver.
class WhatsappProxy::ApplyJob < ApplicationJob
  queue_as :low

  def perform(session_name)
    WhatsappProxy::SessionLock.with(session_name) { apply(session_name) }
  end

  private

  def apply(session_name)
    return if WhatsappProxy::Assignment.find_by(session_name: session_name)&.in_backoff?

    assigner = WhatsappProxy::Assigner.new
    proxy = assigner.for(session_name)
    return if proxy.nil?

    client = Waha::Client.new
    remote = client.get_session(session_name, timeout: WhatsappProxy::SessionUpdater::READ_TIMEOUT)
    return assigner.mark_confirmed!(session_name, proxy) if already_applied?(remote, proxy)

    remember_engine_state(assigner, session_name, remote)
    outcome = WhatsappProxy::SessionUpdater.new(client: client).apply!(session_name, proxy, before: remote)
    record_outcome(assigner, session_name, proxy, outcome, client)
  rescue Waha::Client::NotFound
    Rails.logger.warn("[whatsapp_proxy] session=#{session_name} não existe no motor: atribuição liberada")
    assigner&.release!(session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] troca de proxy falhou session=#{session_name}: #{e.class}")
    record_failure(session_name, &:apply_failed!)
  end

  def record_outcome(assigner, session_name, proxy, outcome, client)
    case outcome
    when :applied
      assigner.mark_applied!(session_name, proxy)
      Rails.logger.info("[whatsapp_proxy] session=#{session_name} agora sai por #{proxy.server}")
    when :rolled_back then failed!(session_name, proxy)
    when :rollback_failed
      server, digest = WhatsappProxy::EngineProxy.read(client, session_name)
      record_failure(session_name) { |assignment| assignment.rollback_failed!(engine_server: server, engine_digest: digest) }
    when :failed then record_failure(session_name, &:apply_failed!)
    when :refused then WhatsappProxy::Assignment.where(session_name: session_name).update_all(apply_scheduled_at: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # O IP que o motor usa agora vira o estado guardado antes do PUT (troca que manteve o IP da tabela, ex. :drift), para
  # a volta voltar a ele — só se for um IP conhecido da lista do plano.
  def remember_engine_state(assigner, session_name, remote)
    assignment = WhatsappProxy::Assignment.find_by(session_name: session_name)
    server, = WhatsappProxy::EngineProxy.from_session(remote)
    return if assignment.nil? || server.nil?

    listed = assigner.pool(assignment.pool).proxies.find { |proxy| WhatsappProxy::Server.same?(proxy.server, server) }
    assignment.remember_engine_state!(listed)
  end

  # O motor voltou à configuração anterior: a atribuição volta junto e entra em recuo.
  def failed!(session_name, proxy)
    assignment = record_failure(session_name, &:revert_failed_apply!)
    return if assignment.nil?
    return unless assignment.apply_failures == 1 || assignment.backoff_exhausted?

    WhatsappProxy::Alert.notify!('troca_desfeita', "troca de proxy da session=#{session_name} para #{proxy.server} desfeita " \
                                                   "(falha #{assignment.apply_failures}); nova tentativa com recuo",
                                 level: :error, session: session_name, ip: proxy.server, count: assignment.apply_failures)
  end

  # Volta que bate em outra conta ou no limite do IP (raro: alguém pegou o IP antigo): fica pendente, sem estado anterior.
  def record_failure(session_name)
    WhatsappProxy::Assignment.exclusively do
      assignment = WhatsappProxy::Assignment.find_by(session_name: session_name)
      next if assignment.nil?

      yield assignment
      assignment
    rescue ActiveRecord::RecordInvalid
      assignment.reload.update!(WhatsappProxy::Assignment::FORGET_PREVIOUS.merge(
                                  proxy_address: nil, proxy_port: nil, webshare_proxy_id: nil, credential_digest: nil,
                                  apply_failures: assignment.apply_failures + 1, last_apply_failed_at: Time.current
                                ))
      assignment
    end
  end

  def already_applied?(remote, proxy)
    server, digest = WhatsappProxy::EngineProxy.from_session(remote)
    WhatsappProxy::Server.same?(server, proxy.server) && digest == proxy.credential_digest
  end
end
