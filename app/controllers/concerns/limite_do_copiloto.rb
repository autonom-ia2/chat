# #1872 — limite de pedidos ao copiloto da Autonom.ia (texto do e-mail e conversa): cada POST é uma
# chamada paga na chave de IA da conta. Roda depois da autenticação, por pessoa na conta
# (account_user). Janela fixa de 60 s (aceita: no pior caso, 2x o limite na virada da janela).
# Estourou: 429 `too_many_requests`. Limite em AUTONOMIA_COPILOT_LIMIT_PER_MINUTE (.env.example).
module LimiteDoCopiloto
  JANELA_DO_LIMITE = 60
  LIMITE_PADRAO = 20

  private

  # Renderiza o 429 e devolve true quando estourou; quem chama encerra a ação.
  def limitar_copiloto!
    return false if contar_pedido_do_copiloto <= limite_do_copiloto

    render json: { error: 'too_many_requests' }, status: :too_many_requests
    true
  end

  # O contador nasce com o prazo (SET NX EX) e só então soma. Se mesmo assim ficar sem prazo
  # (expirou entre os dois comandos, ou uma chave antiga), ganha o prazo aqui: nunca há contador eterno.
  def contar_pedido_do_copiloto
    chave = "autonomia:copilot:limite:#{Current.account_user.id}"
    pedidos = Redis::Alfred.with do |redis|
      redis.set(chave, 0, nx: true, ex: JANELA_DO_LIMITE)
      redis.incr(chave)
    end
    Redis::Alfred.expire(chave, JANELA_DO_LIMITE) if Redis::Alfred.ttl(chave) == -1
    pedidos
  end

  def limite_do_copiloto
    valor = ENV.fetch('AUTONOMIA_COPILOT_LIMIT_PER_MINUTE', '').to_s.strip
    numero = Integer(valor, exception: false)
    numero&.positive? ? numero : LIMITE_PADRAO
  end
end
