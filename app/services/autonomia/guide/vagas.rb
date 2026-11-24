# Quantos trabalhos longos do Guia rodam ao mesmo tempo: um por conta e alguns na instalação inteira (#936).
#
# A vaga é do trabalho enquanto ele anda (entre um lote e outro também) e vence sozinha se o processo morrer sem
# devolver: a validade é renovada a cada lote. O que não consegue vaga fica na fila.
#
# Cada tipo tem as próprias chaves (`prefixo`): a revisão de conversas (#3158) não toma a vaga da tarefa de escrita
# da mesma conta, e vice-versa.
class Autonomia::Guide::Vagas
  VALIDADE = 3.minutes

  def initialize(prefixo, total:)
    @por_conta = "#{prefixo}:conta:"
    @rodando = "#{prefixo}:rodando"
    @trava = "#{prefixo}:semaforo"
    @total = total
  end

  # -> true quando o trabalho tem (ou renovou) a vaga.
  def entrar(trabalho)
    entrou = false
    Redis::LockManager.new.with_lock(@trava, 2) { entrou = reservar(trabalho.id.to_s, trabalho.account_id) }
    entrou
  end

  def sair(trabalho)
    Redis::Alfred.with { |redis| redis.zrem(@rodando, trabalho.id.to_s) }
    Redis::Alfred.delete_if_equals("#{@por_conta}#{trabalho.account_id}", trabalho.id.to_s)
  end

  def reservar(id, account_id)
    agora = Time.current.to_f
    Redis::Alfred.zremrangebyscore(@rodando, '-inf', agora)
    dono = Redis::Alfred.get("#{@por_conta}#{account_id}")
    return false if dono.present? && dono != id
    return false if Redis::Alfred.zscore(@rodando, id).nil? && Redis::Alfred.zcard(@rodando) >= @total

    Redis::Alfred.set("#{@por_conta}#{account_id}", id, ex: VALIDADE.to_i)
    Redis::Alfred.zadd(@rodando, agora + VALIDADE.to_i, id)
    true
  end
end
