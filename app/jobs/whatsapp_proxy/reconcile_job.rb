# Mantém cada número no IP certo (#1516). A cada rodada lê as sessões do motor UMA vez e cada plano da Webshare UMA vez;
# o que fazer com cada atribuição é decidido por WhatsappProxy::Triage (caminhos tristes documentados lá) e a falha
# geral por WhatsappProxy::Outage. Aqui: agenda a troca no motor (WhatsappProxy::ApplyJob, com espera e volta).
# - No máximo MAX_CHANGES por rodada; sessões em recuo nem entram na conta. Urgente (IP sumido com a sessão fora do ar)
#   sai já; o resto sai espaçado (SPACING); número irmão WORKING num IP em quarentena, no máximo 1 por rodada.
# - Instável: o IP só vai para quarentena se houver destino para o número (senão alerta e nada muda), dentro do teto
#   diário do plano, e uma troca dessas por sessão por dia.
# - Erro de um plano da Webshare não para o outro; erro repetido vira alerta `webshare_indisponivel`.
# - O status desta rodada é sempre guardado (base da próxima).
class WhatsappProxy::ReconcileJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_CHANGES = 5
  SPACING = 2.minutes
  PLAN_ERROR_WINDOW = 1.hour.to_i

  def perform
    @assigner = WhatsappProxy::Assigner.new
    return unless @assigner.enabled?

    summarize_unlinked
    managed = managed_assignments
    @outage = WhatsappProxy::Outage.new(engine_sessions, managed, previous: WhatsappProxy::Outage.previous)
    @outage.evaluate!
    pending = triage(managed)
    warn_mass_change(pending, managed)
    scheduled = schedule(pick(pending))
    Rails.logger.info("[whatsapp_proxy] reconciliação: agendadas=#{scheduled} limite=#{MAX_CHANGES}")
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] reconciliação sem o motor: #{e.class}")
  ensure
    WhatsappProxy::Outage.remember!(@engine_sessions) if @engine_sessions
  end

  private

  def engine_sessions
    @engine_sessions ||= Array(Waha::Client.new.list_sessions(all: true))
  end

  def statuses
    @statuses ||= engine_sessions.to_h { |session| [session['name'], session['status'].to_s] }
  end

  # Atribuições que o código cuida e cujo número ainda tem caixa; as sem dono são apagadas (IP volta ao plano).
  def managed_assignments
    WhatsappProxy::Assignment.managed.order(:assigned_at).to_a.select do |assignment|
      next true if WhatsappProxy::SessionOwner.find(assignment.session_name)

      Rails.logger.warn("[whatsapp_proxy] session=#{assignment.session_name} sem caixa: atribuição apagada")
      assignment.destroy!
      false
    end
  end

  # [[assignment, motivo, urgente?]] — um plano com erro na Webshare fica de fora; o outro segue.
  def triage(managed)
    decide = WhatsappProxy::Triage.new(assigner: @assigner, outage: @outage, statuses: statuses)
    managed.filter_map do |assignment|
      next if failed_pools.include?(assignment.pool)

      decision = decide.call(assignment)
      [assignment, *decision] if decision
    rescue Webshare::Client::Error => e
      plan_failed!(assignment.pool, e)
      nil
    end
  end

  # Urgentes primeiro; no máximo um irmão WORKING de IP em quarentena; corta em MAX_CHANGES.
  def pick(pending)
    sibling_taken = false
    ordered = pending.sort_by.with_index { |(_assignment, _reason, urgent), index| [urgent ? 0 : 1, index] }
    ordered.select do |(_assignment, reason, _urgent)|
      next true unless reason == :quarantined_working
      next false if sibling_taken

      sibling_taken = true
    end.first(MAX_CHANGES)
  end

  def schedule(batch)
    spaced = 0
    batch.count do |(assignment, reason, urgent)|
      next false unless prepare(assignment, reason)

      WhatsappProxy::ApplyJob.set(wait: urgent ? 0 : (spaced += 1) * SPACING).perform_later(assignment.session_name)
      true
    rescue ActiveRecord::RecordInvalid => e
      WhatsappProxy::Alert.notify!('atribuicao_invalida', "session=#{assignment.session_name}: atribuição recusada (#{e.class})",
                                   level: :error, session: assignment.session_name)
      false
    rescue Webshare::Client::Error => e
      plan_failed!(assignment.pool, e)
      false
    end
  end

  # Atribui o IP novo antes de agendar a troca. nil do Assigner (plano sem IP, Webshare fora) conta como falha (recuo).
  def prepare(assignment, reason)
    return quarantine_and_move(assignment) if reason == :unstable

    owner = WhatsappProxy::SessionOwner.find(assignment.session_name)
    return true if @assigner.resolve(assignment.session_name, owner, @assigner.pool(owner.pool))

    assignment.reload.apply_failed!
    false
  end

  # Sessão caindo e voltando com IP "válido": só põe o IP em quarentena se houver para onde mover o número.
  def quarantine_and_move(assignment)
    session = assignment.session_name
    return unstable_again!(session) if WhatsappProxy::Health.swapped_today?(session)
    return false unless WhatsappProxy::Quarantine.room?(assignment.pool)

    old_ip = assignment.server
    quarantine = WhatsappProxy::Quarantine.put!(assignment.proxy_address, assignment.pool, "session=#{session} instável", notify: false)
    @assigner.pool(assignment.pool).forget_quarantine!
    moved = moved?(assignment)
    return no_destination!(quarantine, assignment, old_ip) unless moved

    WhatsappProxy::Health.claim_swap!(session)
    WhatsappProxy::Health.reset!(session)
    WhatsappProxy::Quarantine.notify_put(quarantine)
    WhatsappProxy::Alert.notify!('sessao_instavel_trocada', "session=#{session} instável em #{old_ip}: trocando de IP",
                                 session: session, ip: old_ip)
    true
  end

  def moved?(assignment)
    owner = WhatsappProxy::SessionOwner.find(assignment.session_name)
    proxy = @assigner.resolve(assignment.session_name, owner, @assigner.pool(owner.pool))
    proxy.present? && proxy.address != assignment.proxy_address
  end

  def no_destination!(quarantine, assignment, old_ip)
    quarantine.destroy!
    @assigner.pool(assignment.pool).forget_quarantine!
    WhatsappProxy::Alert.notify!('quarentena_sem_destino', "session=#{assignment.session_name} instável em #{old_ip}, mas não " \
                                                           'há IP livre para onde mover: nada mudou',
                                 level: :error, session: assignment.session_name, ip: old_ip, pool: assignment.pool)
    false
  end

  def unstable_again!(session)
    WhatsappProxy::Alert.notify!('sessao_instavel_de_novo', "session=#{session} segue instável depois de trocar de IP hoje: " \
                                                            'o problema não parece ser o proxy', level: :error, session: session)
    false
  end

  def failed_pools
    @failed_pools ||= []
  end

  # Erro de lista/plano (inclusive 401/429): o plano sai desta rodada; repetido na janela, alerta.
  def plan_failed!(pool, error)
    failed_pools << pool
    Rails.logger.warn("[whatsapp_proxy] plano #{pool} indisponível nesta rodada: #{error.message}")
    key = "whatsapp_proxy:plan_errors:#{pool}"
    count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, PLAN_ERROR_WINDOW)
    return if count.to_i < 2

    WhatsappProxy::Alert.notify!('webshare_indisponivel', "plano #{pool}: #{count} erros seguidos da Webshare (#{error.message})",
                                 level: :error, pool: pool, count: count)
  rescue Redis::BaseError
    nil
  end

  def warn_mass_change(pending, managed)
    gone = pending.count { |(_assignment, reason)| reason == :gone }
    return unless gone * 2 > managed.size

    WhatsappProxy::Alert.notify!('troca_em_massa', "#{gone} de #{managed.size} IPs atribuídos sumiram da lista da Webshare. " \
                                                   "Trocando no máximo #{MAX_CHANGES} por rodada.",
                                 level: :error, count: gone, total: managed.size)
  end

  def summarize_unlinked
    day, count = WhatsappProxy::Health.unlinked_summary!
    return if day.nil?

    WhatsappProxy::Alert.notify!('aparelho_desvinculado', "#{count} sessão(ões) pediram QR em #{day} (aparelho desvinculado; " \
                                                          'não é o proxy, nada foi trocado)', count: count, date: day.to_s)
  end
end
