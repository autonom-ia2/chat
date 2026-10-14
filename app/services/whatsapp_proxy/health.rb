# Saúde de uma sessão com proxy (#1516). Um IP ruim não some da lista da Webshare: a sessão fica alternando
# STARTING/WORKING no motor. Dois sinais, só de status do motor (nada de interpretar texto de log):
# - rodadas da reconciliação seguidas fora de WORKING (STARTING ou FAILED): UNSTABLE_ROUNDS. Só conta a sessão que
#   CAIU — estava WORKING na rodada anterior (ou já está numa sequência que começou assim). FAILED antiga, que nunca
#   esteve WORKING, não conta e não queima IP bom. Voltou a WORKING, zera;
# - quedas avisadas pelo webhook do Híbrido (conectado → conectando/falhou) dentro de DROP_WINDOW: MAX_DROPS.
# SCAN_QR_CODE é aparelho desvinculado, não proxy: zera a contagem e entra no resumo do dia (um aviso por dia).
# Contadores no Redis: com ele fora, nada é contado e nenhuma troca acontece (falha segura).
module WhatsappProxy::Health
  module_function

  UNSTABLE_STATUSES = %w[STARTING FAILED].freeze
  UNSTABLE_ROUNDS = 2
  MAX_DROPS = 3
  DROP_WINDOW = 30.minutes.to_i
  ROUNDS_TTL = 2.hours.to_i
  # Uma troca por instabilidade por sessão a cada 24 h: se continuar caindo, o problema não é o IP.
  SWAP_COOLDOWN = 24.hours.to_i
  DAY_TTL = 3.days.to_i

  # :unstable ou nil. previous: status da sessão na rodada anterior (nil quando desconhecido).
  def observe!(session_name, status, previous:)
    case status
    when 'WORKING' then redis { ::Redis::Alfred.delete(rounds_key(session_name)) && ::Redis::Alfred.delete(eligible_key(session_name)) }
    when 'SCAN_QR_CODE' then return unlinked!(session_name)
    when *UNSTABLE_STATUSES then rounds = count_round(session_name, previous)
    end
    :unstable if rounds.to_i >= UNSTABLE_ROUNDS || drops(session_name) >= MAX_DROPS
  end

  def count_round(session_name, previous)
    return unless previous == 'WORKING' || rounds(session_name).positive? || eligible?(session_name)

    count = redis { ::Redis::Alfred.incr(rounds_key(session_name)) }
    redis { ::Redis::Alfred.expire(rounds_key(session_name), ROUNDS_TTL) }
    count
  end

  def rounds(session_name)
    redis { ::Redis::Alfred.get(rounds_key(session_name)) }.to_i
  end

  # Fim de uma falha geral: quem segue fora pode passar a contar uma a uma, do zero, a partir da PRÓXIMA rodada
  # (precisa de UNSTABLE_ROUNDS rodadas novas fora). Sem isto nunca contaria (não estava WORKING antes).
  def eligible!(session_name)
    reset!(session_name)
    redis { ::Redis::Alfred.setex(eligible_key(session_name), '1', ROUNDS_TTL) }
  end

  def eligible?(session_name)
    redis { ::Redis::Alfred.get(eligible_key(session_name)) }.present?
  end

  def eligible_key(session_name)
    "whatsapp_proxy:eligible:#{session_name}"
  end

  # pool: o plano da sessão (o webhook é do Híbrido: isp). Recurso desligado ou falha geral: não conta.
  def record_drop!(session_name, pool: 'isp')
    return unless WhatsappProxy::Assigner.feature_enabled?
    return if WhatsappProxy::Outage.active?(pool)

    count = redis { ::Redis::Alfred.incr(drops_key(session_name)) }
    redis { ::Redis::Alfred.expire(drops_key(session_name), DROP_WINDOW) } if count.to_i == 1
  end

  # true na primeira troca do dia por instabilidade; false quando já trocou (aí só avisa).
  def claim_swap!(session_name)
    redis { ::Redis::Alfred.set("whatsapp_proxy:unstable_swap:#{session_name}", '1', nx: true, ex: SWAP_COOLDOWN) } ? true : false
  end

  def swapped_today?(session_name)
    redis { ::Redis::Alfred.get("whatsapp_proxy:unstable_swap:#{session_name}") }.present?
  end

  def reset!(session_name)
    redis { ::Redis::Alfred.delete(rounds_key(session_name)) }
    redis { ::Redis::Alfred.delete(drops_key(session_name)) }
  end

  def drops(session_name)
    redis { ::Redis::Alfred.get(drops_key(session_name)) }.to_i
  end

  # Conta a sessão (uma vez por dia) no resumo de aparelhos desvinculados do dia.
  def unlinked!(session_name, today: Date.current)
    reset!(session_name)
    first = redis { ::Redis::Alfred.set("whatsapp_proxy:unlinked:#{today}:#{session_name}", '1', nx: true, ex: DAY_TTL) }
    redis { ::Redis::Alfred.incr(unlinked_count_key(today)) && ::Redis::Alfred.expire(unlinked_count_key(today), DAY_TTL) } if first
    nil
  end

  # [data, quantidade] do dia anterior, uma vez só (o primeiro que pedir leva); nil quando não há o que avisar.
  def unlinked_summary!(today: Date.current)
    yesterday = today - 1
    count = redis { ::Redis::Alfred.get(unlinked_count_key(yesterday)) }.to_i
    return if count.zero?
    return unless redis { ::Redis::Alfred.set("whatsapp_proxy:unlinked_summary:#{yesterday}", '1', nx: true, ex: DAY_TTL) }

    [yesterday, count]
  end

  def unlinked_count_key(day)
    "whatsapp_proxy:unlinked_count:#{day}"
  end

  def rounds_key(session_name)
    "whatsapp_proxy:unstable_rounds:#{session_name}"
  end

  def drops_key(session_name)
    "whatsapp_proxy:drops:#{session_name}"
  end

  def redis
    yield
  rescue Redis::BaseError
    nil
  end
end
