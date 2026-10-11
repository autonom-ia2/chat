# "Esta conta tem alguma linha de acesso por funil?" (#1148). Tempo real, notificações e contadores perguntam isto a
# cada evento de todas as contas; quase nenhuma tem acesso configurado. O sim/não fica em Redis por conta: sem linha,
# nenhuma consulta à tabela.
#
# É uma regra de permissão, então erra só para o lado fechado:
# - quem lê grava com SET NX: nunca sobrescreve a chave que outro escreveu (um "0" calculado antes de uma criação não
#   apaga o "1" que a criação gravou);
# - criar acesso grava "1" (after_commit on: :create); apagar só remove a chave (um "1" velho custa consultas a mais,
#   não abre nada). Remoção em cascata pela FK (conta, caixa ou usuário apagados) não roda callback e deixa "1": seguro.
# - Inserir linha por SQL direto ou insert_all exige `Crm::Access::AccountFlag.mark_present!(account_id)` manual.
module Crm::Access::AccountFlag
  KEY = 'crm:access:any:%<account_id>s'.freeze
  TTL = 1.day.to_i

  module_function

  def any?(account_id)
    cached = Redis::Alfred.get(key(account_id))
    return cached == '1' unless cached.nil?

    found = Crm::InboxAgentAccess.exists?(account_id: account_id)
    Redis::Alfred.set(key(account_id), found ? '1' : '0', nx: true, ex: TTL)
    # Outro processo pode ter gravado antes (ex.: a criação de um acesso): vale o que está na chave.
    Redis::Alfred.get(key(account_id)) == '1' || found
  end

  def mark_present!(account_id)
    Redis::Alfred.set(key(account_id), '1', ex: TTL)
  end

  def reset!(account_id)
    Redis::Alfred.delete(key(account_id))
  end

  def key(account_id)
    format(KEY, account_id: account_id)
  end
end
