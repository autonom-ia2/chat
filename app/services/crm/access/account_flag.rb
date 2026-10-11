# "Esta conta tem alguma linha de acesso por funil?" (#1148). Tempo real, notificações e contadores perguntam isto a
# cada evento de todas as contas; quase nenhuma tem acesso configurado. O sim/não fica em Redis por conta e vence quando
# uma linha é criada ou apagada (after_commit do Crm::InboxAgentAccess): sem linha, nenhuma consulta à tabela.
module Crm::Access::AccountFlag
  KEY = 'crm:access:any:%<account_id>s'.freeze
  TTL = 1.day

  module_function

  def any?(account_id)
    cached = Redis::Alfred.get(key(account_id))
    return cached == '1' unless cached.nil?

    found = Crm::InboxAgentAccess.exists?(account_id: account_id)
    Redis::Alfred.setex(key(account_id), found ? '1' : '0', TTL)
    found
  end

  def reset!(account_id)
    Redis::Alfred.delete(key(account_id))
  end

  def key(account_id)
    format(KEY, account_id: account_id)
  end
end
