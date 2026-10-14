# Sessão caindo e voltando com IP que a Webshare ainda chama de válido (#1516): o IP sai de circulação (quarentena de
# 24 h) e o número ganha outro do mesmo plano e fatia. Ordem pensada para nunca mexer à toa:
# `ready?` (antes do corte das vagas da rodada, sem gravar nada):
# 1. uma troca dessas por sessão por dia (se continuar caindo, o problema não é o IP: alerta 1x por dia);
# 2. teto de quarentenas do plano (WhatsappProxy::Quarantine.room?);
# 3. há para onde mover? Sem IP livre: `quarentena_sem_destino`; motor ilegível: `motor_indisponivel` (1x por dia).
# `call`: quarentena provisória, sem alerta → reatribui → só então avisa. Reatribuição que falha (sem IP, registro
# recusado) desfaz a quarentena — registro que já existia volta ao estado de antes.
class WhatsappProxy::UnstableSwap
  DAILY = 1.day

  def initialize(assigner)
    @assigner = assigner
  end

  def ready?(assignment)
    session = assignment.session_name
    return daily_alert('sessao_instavel_de_novo', assignment, 'segue instável depois de trocar de IP hoje') if swapped_today?(session)
    return false unless WhatsappProxy::Quarantine.room?(assignment.pool)

    destination = @assigner.destination?(session, owner(session), excluding: assignment.proxy_address)
    return daily_alert('motor_indisponivel', assignment, 'o motor não listou as sessões: troca adiada') if destination == :engine_down
    return daily_alert('quarentena_sem_destino', assignment, 'não há IP livre para onde mover: nada mudou') unless destination

    true
  end

  # true quando o número já ganhou o IP novo (a troca no motor pode ser agendada).
  def call(assignment)
    return false unless ready?(assignment)

    move(assignment)
  end

  private

  def swapped_today?(session)
    WhatsappProxy::Health.swapped_today?(session)
  end

  def owner(session)
    WhatsappProxy::SessionOwner.find(session)
  end

  def move(assignment)
    old_ip = assignment.server
    quarantine, before = WhatsappProxy::Quarantine.provisional!(assignment.proxy_address, assignment.pool,
                                                                "session=#{assignment.session_name} instável")
    forget_quarantine(assignment)
    proxy = resolve(assignment, quarantine, before)
    unless proxy && proxy.address != assignment.proxy_address
      undo(quarantine, before, assignment)
      return daily_alert('quarentena_sem_destino', assignment, 'não há IP livre para onde mover: nada mudou')
    end

    announce(assignment.session_name, old_ip, quarantine)
    true
  end

  def resolve(assignment, quarantine, before)
    @assigner.resolve(assignment.session_name, owner(assignment.session_name), @assigner.pool(owner(assignment.session_name).pool))
  rescue ActiveRecord::RecordInvalid
    undo(quarantine, before, assignment)
    raise
  end

  def undo(quarantine, before, assignment)
    quarantine.undo!(before)
    forget_quarantine(assignment)
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

  def daily_alert(code, assignment, text)
    WhatsappProxy::Alert.notify!(code, "session=#{assignment.session_name} instável em #{assignment.server}: #{text}",
                                 level: :error, session: assignment.session_name, ip: assignment.server, pool: assignment.pool,
                                 subject: "#{assignment.session_name}:#{Date.current}", window: DAILY)
    false
  end
end
