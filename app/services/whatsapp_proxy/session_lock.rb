# Uma troca de proxy por sessão de cada vez (#1516): ApplyJob e a rake de migrar disputam a mesma trava. Token único,
# solta só quem pegou (compare-and-delete), TTL acima do pior caso do SessionUpdater (37 leituras de 8 s + 175 s de
# espera + PUT, apps e volta ≈ 9 min).
module WhatsappProxy::SessionLock
  module_function

  TTL = 15.minutes.to_i

  def key(session_name)
    "whatsapp_proxy:apply:#{session_name}"
  end

  # Executa o bloco com a trava; sem conseguir, devolve :locked sem executar.
  def with(session_name)
    token = SecureRandom.hex(16)
    return :locked unless ::Redis::Alfred.set(key(session_name), token, nx: true, ex: TTL)

    begin
      yield
    ensure
      ::Redis::Alfred.delete_if_equals(key(session_name), token)
    end
  end
end
