# AS RECUSAS RECENTES DE UMA CONVERSA, para a nota da equipe no encaminhamento (conversa 7057, 24/09/2026).
#
# A busca de atividade estourou o tempo duas vezes, a Lia disse ao cliente que alguém da equipe assumia, e a equipe
# recebeu a conversa sem saber por quê: a recusa só ia para o log. Aqui cada recusa com conversa deixa o CÓDIGO do
# motivo (nunca dado do cliente, nunca texto da conversa) numa lista curta no Redis, que o encaminhamento recolhe
# (`NotaDoEncaminhamento`) e apaga. Sem encaminhamento, a lista expira sozinha.
#
# NUNCA LEVANTA, como o próprio registro da recusa: é cortesia sobre um caminho que já deu errado.
module Autonomia::Agents::Tools::RecusasRecentes
  CHAVE = 'autonomia:recusas_recentes:%<conversa>d'.freeze
  VALIDADE = 30.minutes
  TETO = 20

  module_function

  def anotar(conversa_id, motivo)
    return if conversa_id.blank? || motivo.blank? || motivo == '-'

    chave = format(CHAVE, conversa: conversa_id)
    Redis::Alfred.lpush(chave, motivo)
    Redis::Alfred.with { |redis| redis.ltrim(chave, 0, TETO - 1) }
    Redis::Alfred.expire(chave, VALIDADE.to_i)
    nil
  rescue StandardError
    nil
  end

  # -> os motivos, do mais antigo ao mais novo, e a lista apagada. [] sem nada ou se o Redis falhar.
  def retirar(conversa_id)
    chave = format(CHAVE, conversa: conversa_id)
    motivos = Redis::Alfred.lrange(chave).reverse
    Redis::Alfred.delete(chave)
    motivos
  rescue StandardError
    []
  end
end
