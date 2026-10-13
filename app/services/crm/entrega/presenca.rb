# Quem está online, para o motor de entrega (#1454). Dentro de uma rodada da fila (HandoffDrainJob), a presença de cada
# conta é lida uma vez só: centenas de conversas da mesma conta não viram centenas de leituras no Redis. Fora da rodada,
# lê na hora.
module Crm::Entrega::Presenca
  CHAVE = :crm_entrega_presenca_da_rodada

  module_function

  def na_rodada
    anterior = Thread.current[CHAVE]
    Thread.current[CHAVE] = {}
    yield
  ensure
    Thread.current[CHAVE] = anterior
  end

  def online_ids(account_id)
    cache = Thread.current[CHAVE]
    return ler(account_id) unless cache

    cache.fetch(account_id) { cache[account_id] = ler(account_id) }
  end

  def ler(account_id)
    OnlineStatusTracker.get_available_users(account_id).select { |_id, status| status == 'online' }.keys.map(&:to_i)
  end
end
