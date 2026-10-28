# Quantas vezes seguidas (entre rodadas) cada conversa deu problema na leitura automática do painel (#2301), por tipo,
# no Redis, com validade POR. Chegou ao limite do tipo, o orquestrador marca a conversa como não lida e ela só volta à
# fila com mensagem nova: senão pagaria uma chamada por dia para sempre.
#
# - `falhas`: a resposta recusada (fora do catálogo, JSON quebrado), culpa da conversa;
# - `inesperados`: um bug do sistema naquela conversa (na gravação, na transcrição);
# - `passageiras`: só o tempo esgotado da chamada (a OpenAI fora do ar, 429 e 5xx não contam: não são culpa da
#   conversa). É o caso da conversa que estoura o tempo toda vez: a OpenAI cobra a chamada, mas o consumo não é gravado
#   e não entra no teto.
class Autonomia::Desempenho::LeituraAutomatica::VezesDaConversa
  LIMITES = { 'falhas' => 2, 'inesperados' => 5, 'passageiras' => 3 }.freeze
  POR = 7.days

  def initialize(account:, ficha:)
    @prefixo = "autonomia:desempenho:leitura:#{account.id}:#{ficha.sujeito_type}:#{ficha.sujeito_id}"
  end

  # Mais uma vez do tipo para a conversa; true quando chegou ao limite (hora de desistir dela).
  def mais_uma?(tipo, conversation_id)
    chave = chave(tipo, conversation_id)
    vezes = Redis::Alfred.incr(chave).to_i
    Redis::Alfred.expire(chave, POR.to_i)
    vezes >= LIMITES.fetch(tipo)
  end

  def esquecer(tipo, conversation_id)
    Redis::Alfred.delete(chave(tipo, conversation_id))
  end

  # A conversa foi lida: todos os contadores dela voltam a zero.
  def zerar(conversation_id)
    LIMITES.each_key { |tipo| esquecer(tipo, conversation_id) }
  end

  private

  def chave(tipo, conversation_id) = "#{@prefixo}:#{tipo}:#{conversation_id}"
end
