# Sessão caindo e voltando com IP que a Webshare ainda chama de válido (#1516): o IP sai de circulação (quarentena de
# 24 h) e o número ganha outro do mesmo plano e fatia. Ordem pensada para nunca mexer à toa:
# 1. uma troca dessas por sessão por dia (se continuar caindo, o problema não é o IP: alerta 1x por dia);
# 2. teto de quarentenas do plano (WhatsappProxy::Quarantine.room?);
# 3. há para onde mover? Checagem só de leitura; sem destino, nem põe quarentena (alerta 1x por dia);
# 4. quarentena provisória, sem alerta → reatribui → só então avisa. Se a reatribuição falhar (sem IP ou registro
#    recusado), a quarentena é desfeita.
class WhatsappProxy::UnstableSwap
  DAILY = 1.day

  def initialize(assigner)
    @assigner = assigner
  end

  # true quando o número já ganhou o IP novo (a troca no motor pode ser agendada).
  def call(assignment)
    session = assignment.session_name
    return unstable_again!(session) if WhatsappProxy::Health.swapped_today?(session)
    return false unless WhatsappProxy::Quarantine.room?(assignment.pool)

    owner = WhatsappProxy::SessionOwner.find(session)
    return no_destination!(assignment) unless @assigner.destination?(session, owner, excluding: assignment.proxy_address)

    move(assignment, owner)
  end

  private

  def move(assignment, owner)
    old_ip = assignment.server
    quarantine = WhatsappProxy::Quarantine.put!(assignment.proxy_address, assignment.pool,
                                                "session=#{assignment.session_name} instável", notify: false)
    forget_quarantine(assignment)
    proxy = resolve(assignment, owner, quarantine)
    return undo(quarantine, assignment) && no_destination!(assignment) unless proxy && proxy.address != assignment.proxy_address

    announce(assignment.session_name, old_ip, quarantine)
    true
  end

  def resolve(assignment, owner, quarantine)
    @assigner.resolve(assignment.session_name, owner, @assigner.pool(owner.pool))
  rescue ActiveRecord::RecordInvalid
    undo(quarantine, assignment)
    raise
  end

  def undo(quarantine, assignment)
    quarantine.destroy!
    forget_quarantine(assignment)
    true
  end

  def forget_quarantine(assignment)
    @assigner.pool(assignment.pool).forget_quarantine!
  end

  def announce(session, old_ip, quarantine)
    WhatsappProxy::Health.claim_swap!(session)
    WhatsappProxy::Health.reset!(session)
    WhatsappProxy::Quarantine.notify_put(quarantine)
    WhatsappProxy::Alert.notify!('sessao_instavel_trocada', "session=#{session} instável em #{old_ip}: trocando de IP",
                                 session: session, ip: old_ip)
  end

  def no_destination!(assignment)
    WhatsappProxy::Alert.notify!('quarentena_sem_destino', "session=#{assignment.session_name} instável em #{assignment.server}, " \
                                                           'mas não há IP livre para onde mover: nada mudou',
                                 level: :error, session: assignment.session_name, ip: assignment.server, pool: assignment.pool,
                                 subject: "#{assignment.session_name}:#{Date.current}", window: DAILY)
    false
  end

  def unstable_again!(session)
    WhatsappProxy::Alert.notify!('sessao_instavel_de_novo', "session=#{session} segue instável depois de trocar de IP hoje: " \
                                                            'o problema não parece ser o proxy',
                                 level: :error, session: session, subject: "#{session}:#{Date.current}", window: DAILY)
    false
  end
end
