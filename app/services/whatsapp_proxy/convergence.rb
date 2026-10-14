# Convergência com o motor (#1516): o motor é a fonte da verdade. A cada rodada a reconciliação já tem a lista de
# sessões do motor; aqui a atribuição gerenciada é comparada com o proxy que o motor usa de fato (host:porta normalizado
# e HMAC da credencial). Não compara: troca agendada há pouco (`in_flight?`), troca em andamento (SessionLock ocupada).
# - Mesmo IP: a tabela registra a credencial que o motor usa — salvo credencial mascarada (alerta 1x, nada regravado).
# - IP diferente, sessão WORKING e o IP do motor OFERECÍVEL (na lista, válido, BR, na fatia, sem quarentena, não
#   reservado) do plano da sessão, sem outro número de fora da conta nele no motor e dentro do limite por IP: a TABELA
#   passa a ser o motor (sem PUT, sem reinício).
# - Importada cujo motor passou a usar proxy fora da Webshare (posto à mão depois): vira externa — o código para de
#   gerenciar e nunca sobrescreve (alerta 1x `proxy_manual_detectado`).
# - Qualquer outro caso de IP diferente (sumido, inválido, em quarentena, de outra conta, outro plano, sessão fora de
#   WORKING): troca normal (:drift) para o IP da tabela. Motor sem proxy: reaplica (:drift).
class WhatsappProxy::Convergence
  OFF = WhatsappProxy::Health::UNSTABLE_STATUSES
  ONCE = 30.days

  # sessions: as sessões do motor desta rodada, por nome.
  def initialize(assigner, sessions)
    @assigner = assigner
    @sessions = sessions
  end

  # nil (convergido, ou a tabela foi ajustada ao motor) ou [:drift, urgente?].
  def call(assignment, session, status, owner)
    return unless comparable?(assignment)

    server, digest = WhatsappProxy::EngineProxy.from_session(session)
    return [:drift, OFF.include?(status)] if server.nil?
    return record_engine_credential(assignment, session, digest) if WhatsappProxy::Server.same?(server, assignment.server)
    return manual_proxy!(assignment, server) if manual_proxy?(assignment, server)

    diverged(assignment, server, digest, status, owner)
  end

  private

  def comparable?(assignment)
    !(assignment.pending? || assignment.external? || assignment.in_flight? || locked?(assignment))
  end

  def locked?(assignment)
    ::Redis::Alfred.get(WhatsappProxy::SessionLock.key(assignment.session_name)).present?
  rescue Redis::BaseError
    true
  end

  def record_engine_credential(assignment, session, digest)
    return masked!(assignment) if WhatsappProxy::EngineProxy.masked?(session)
    return if digest == assignment.credential_digest && !assignment.awaiting_confirmation?

    assignment.update!(assignment.settled.merge(credential_digest: digest))
    nil
  end

  def masked!(assignment)
    return unless first_time?("whatsapp_proxy:masked_seen:#{assignment.session_name}")

    WhatsappProxy::Alert.notify!('credencial_mascarada', "session=#{assignment.session_name}: o motor devolveu a credencial do " \
                                                         'proxy mascarada; nada foi regravado nem reaplicado',
                                 session: assignment.session_name, subject: assignment.session_name, window: ONCE)
    nil
  end

  # Importada e o motor está num proxy que não é de nenhum plano da Webshare: posto à mão depois da importação.
  def first_time?(key)
    ::Redis::Alfred.set(key, '1', nx: true, ex: ONCE.to_i) ? true : false
  rescue Redis::BaseError
    false
  end

  def manual_proxy?(assignment, server)
    return false unless assignment.imported?

    WhatsappProxy::Assignment::POOLS.none? do |name|
      @assigner.pool(name).proxies.any? { |proxy| WhatsappProxy::Server.same?(proxy.server, server) }
    end
  rescue Webshare::Client::Error
    false
  end

  def manual_proxy!(assignment, server)
    assignment.mark_external!(server)
    WhatsappProxy::Alert.notify!('proxy_manual_detectado', "session=#{assignment.session_name}: o motor usa um proxy fora da " \
                                                           "Webshare (#{server}); a atribuição passou a ser externa",
                                 session: assignment.session_name, ip: server, subject: assignment.session_name, window: ONCE)
    nil
  end

  # IP diferente: WORKING com IP oferecível da conta → a tabela vira o motor; senão, troca para o IP da tabela.
  def diverged(assignment, server, digest, status, owner)
    adopt(assignment, server, digest, owner) if status == 'WORKING'
    [:drift, OFF.include?(status)] unless WhatsappProxy::Server.same?(server, assignment.reload.server)
  end

  def adopt(assignment, server, digest, owner)
    listed = @assigner.pool(owner.pool).candidates.find { |proxy| WhatsappProxy::Server.same?(proxy.server, server) }
    return if listed.nil? || foreign_in_engine?(assignment, listed, owner)

    WhatsappProxy::Assignment.exclusively do
      next if WhatsappProxy::Assignment.sharing_ip(listed.address, except_session: assignment.session_name)
                                       .where.not(account_id: owner.account_id).exists?

      assignment.adopt!(listed, digest, owner)
      Rails.logger.info("[whatsapp_proxy] session=#{assignment.session_name}: tabela ajustada ao motor (#{listed.server})")
    end
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Outra sessão do motor usa o mesmo IP e não é um número desta conta registrado nesse IP (mesmo critério do Assigner).
  def foreign_in_engine?(assignment, listed, owner)
    known = WhatsappProxy::Assignment.where(account_id: owner.account_id, proxy_address: listed.address).pluck(:session_name)
    @sessions.any? do |name, session|
      next false if name == assignment.session_name || known.include?(name)

      WhatsappProxy::Server.host(session.dig('config', 'proxy', 'server')) == listed.address
    end
  end
end
