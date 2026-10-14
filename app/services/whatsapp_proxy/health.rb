# Saúde de uma sessão com proxy (#1516). Um IP ruim não some da lista da Webshare: a sessão fica alternando
# STARTING/WORKING no motor. Dois sinais, só de status do motor (nada de interpretar texto de log):
# - rodadas da reconciliação seguidas fora de WORKING (STARTING ou FAILED): UNSTABLE_ROUNDS;
# - quedas avisadas pelo webhook do Híbrido (conectado → conectando/falhou) dentro de DROP_WINDOW: MAX_DROPS.
# SCAN_QR_CODE é aparelho desvinculado, não proxy: zera a contagem e só avisa (uma vez por dia).
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

  # :unstable, :scan_qr ou nil, a partir do status atual da sessão no motor.
  def observe!(session_name, status)
    case status
    when 'WORKING' then redis { ::Redis::Alfred.delete(rounds_key(session_name)) }
    when 'SCAN_QR_CODE' then return scan_qr!(session_name)
    when *UNSTABLE_STATUSES then rounds = redis { ::Redis::Alfred.incr(rounds_key(session_name)) }
    end
    redis { ::Redis::Alfred.expire(rounds_key(session_name), ROUNDS_TTL) } if rounds
    :unstable if rounds.to_i >= UNSTABLE_ROUNDS || drops(session_name) >= MAX_DROPS
  end

  def record_drop!(session_name)
    count = redis { ::Redis::Alfred.incr(drops_key(session_name)) }
    redis { ::Redis::Alfred.expire(drops_key(session_name), DROP_WINDOW) } if count.to_i == 1
  end

  # true na primeira troca do dia por instabilidade; false quando já trocou (aí só avisa).
  def claim_swap!(session_name)
    redis { ::Redis::Alfred.set("whatsapp_proxy:unstable_swap:#{session_name}", '1', nx: true, ex: SWAP_COOLDOWN) } ? true : false
  end

  def reset!(session_name)
    redis { ::Redis::Alfred.delete(rounds_key(session_name)) }
    redis { ::Redis::Alfred.delete(drops_key(session_name)) }
  end

  def drops(session_name)
    redis { ::Redis::Alfred.get(drops_key(session_name)) }.to_i
  end

  def scan_qr!(session_name)
    reset!(session_name)
    first = redis { ::Redis::Alfred.set("whatsapp_proxy:scan_qr:#{session_name}", '1', nx: true, ex: SWAP_COOLDOWN) }
    first ? :scan_qr : nil
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
