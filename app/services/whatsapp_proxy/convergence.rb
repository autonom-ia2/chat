# Convergência com o motor (#1516): o motor é a fonte da verdade. A cada rodada a reconciliação já tem a lista de
# sessões do motor; aqui a atribuição gerenciada é comparada com o proxy que o motor usa de fato (host:porta normalizado
# e HMAC da credencial). Troca agendada há pouco (`in_flight?`) espera: a divergência é esperada até ela terminar.
# - Mesmo IP: a tabela registra a credencial que o motor usa (e esquece estado anterior pendurado). Credencial diferente
#   da lista é com a regra :credential da Triage.
# - IP diferente, sessão WORKING e o IP do motor válido na lista, da mesma conta e plano: a TABELA passa a ser o motor
#   (sem PUT, sem reinício).
# - IP do motor que não existe mais, inválido, de outra conta, ou sessão fora de WORKING: troca normal (:drift) para o
#   IP da tabela — com recuo, trava e as recusas de QR/STOPPED de sempre.
# - Motor sem proxy e atribuição com IP: reaplica (:drift).
class WhatsappProxy::Convergence
  OFF = WhatsappProxy::Health::UNSTABLE_STATUSES

  def initialize(assigner)
    @assigner = assigner
  end

  # nil (convergido, ou a tabela foi ajustada ao motor) ou [:drift, urgente?].
  def call(assignment, session, status, owner)
    return if assignment.pending? || assignment.external? || assignment.in_flight?

    server, digest = WhatsappProxy::EngineProxy.from_session(session)
    return [:drift, OFF.include?(status)] if server.nil?
    return record_engine_credential(assignment, digest) if WhatsappProxy::Server.same?(server, assignment.server)

    diverged(assignment, server, digest, status, owner)
  end

  private

  # IP diferente: WORKING com IP válido da conta → a tabela vira o motor; senão, troca para o IP da tabela.
  def diverged(assignment, server, digest, status, owner)
    adopt(assignment, server, digest, owner) if status == 'WORKING'
    [:drift, OFF.include?(status)] unless WhatsappProxy::Server.same?(server, assignment.reload.server)
  end

  def record_engine_credential(assignment, digest)
    return if digest == assignment.credential_digest && !assignment.awaiting_confirmation?

    assignment.update!(assignment.settled.merge(credential_digest: digest))
    nil
  end

  # A tabela passa a ser o IP do motor, se ele é válido na lista do plano da sessão e pode ser desta conta.
  def adopt(assignment, server, digest, owner)
    listed = engine_proxy_on_list(server, owner)
    return if listed.nil?

    WhatsappProxy::Assignment.exclusively do
      next if WhatsappProxy::Assignment.sharing_ip(listed.address, except_session: assignment.session_name)
                                       .where.not(account_id: owner.account_id).exists?

      assignment.adopt!(listed, digest, owner)
      Rails.logger.info("[whatsapp_proxy] session=#{assignment.session_name}: tabela ajustada ao motor (#{listed.server})")
    end
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def engine_proxy_on_list(server, owner)
    pool = @assigner.pool(owner.pool)
    pool.proxies.find do |proxy|
      WhatsappProxy::Server.same?(proxy.server, server) && pool.serving_ignoring_quarantine?(proxy.address, proxy.port)
    end
  end
end
