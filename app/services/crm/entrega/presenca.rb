# Quem está online, para o motor de entrega (#1454). Dentro de uma rodada da fila (HandoffDrainJob), a presença de cada
# conta é lida uma vez só: centenas de conversas da mesma conta não viram centenas de leituras no Redis. A falha também
# fica guardada na rodada (Redis fora do ar não é relido a cada conversa). Fora da rodada, lê na hora.
#
# Guardado em variável da thread (thread_variable_*), e não em Thread.current[] (que é por fiber): o job roda a rodada
# inteira numa thread do Sidekiq, e o `ensure` devolve o valor anterior, então nada vaza para o job seguinte.
module Crm::Entrega::Presenca
  CHAVE = :crm_entrega_presenca_da_rodada

  module_function

  def na_rodada
    anterior = Thread.current.thread_variable_get(CHAVE)
    Thread.current.thread_variable_set(CHAVE, {})
    yield
  ensure
    Thread.current.thread_variable_set(CHAVE, anterior)
  end

  # O ponto único de quem pergunta "quem está online" para entregar (o seletor e o dono da R13 na Crm::Entrega): qualquer
  # falha da leitura vira PresencaIndisponivel, com log só de ids. Presença fora do ar não é "ninguém online": quem chama
  # segura, e a fila tenta de novo (#1454).
  def online_ids!(account_id)
    online_ids(account_id)
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] presença indisponível conta=#{account_id} erro=#{e.class}")
    raise Crm::Ai::HandoffMemberSelector::PresencaIndisponivel, e.class.name
  end

  def online_ids(account_id)
    cache = Thread.current.thread_variable_get(CHAVE)
    return ler(account_id) unless cache

    resultado = cache.fetch(account_id) { cache[account_id] = ler_guardando_falha(account_id) }
    raise resultado if resultado.is_a?(StandardError)

    resultado
  end

  def ler_guardando_falha(account_id)
    ler(account_id)
  rescue StandardError => e
    e
  end

  def ler(account_id)
    OnlineStatusTracker.get_available_users(account_id).select { |_id, status| status == 'online' }.keys.map(&:to_i)
  end
end
