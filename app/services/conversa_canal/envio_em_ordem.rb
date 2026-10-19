# #1865 — antes de uma mensagem sair, o chat2you pode ter trabalho a fazer (salvar o contato na agenda do aparelho,
# marcar a conversa como lida), e isso leva alguns segundos na primeira vez. Sem cuidado, a mensagem seguinte da mesma
# conversa, que não tem trabalho, sairia antes. Aqui a mensagem com trabalho segura a conversa até sair; as outras da
# mesma conversa esperam (até ESPERA_MAXIMA) antes de seguir. Mensagem sem trabalho e sem ninguém na frente não paga nada.
# A trava tem dono (token) e prazo (TTL); Redis fora do ar não trava o envio: segue sem ordem, com log.
module ConversaCanal::EnvioEmOrdem
  TTL = 60
  ESPERA_MAXIMA = 15
  PASSO_DA_ESPERA = 0.2
  TENTATIVAS = 3

  module_function

  # trabalho: lambda que diz se esta mensagem tem algo a fazer antes de sair. O bloco é o trabalho mais o envio.
  def executar(conversation, trabalho, &)
    chave = "conversa_canal:envio_em_ordem:#{conversation.id}"
    TENTATIVAS.times do
      esperar(chave)
      return yield unless trabalho.call

      token = SecureRandom.hex(8)
      return segurando(chave, token, &) if travar(chave, token)
    end
    yield
  end

  def segurando(chave, token)
    yield
  ensure
    soltar(chave, token)
  end

  def esperar(chave)
    limite = ESPERA_MAXIMA.seconds.from_now
    Kernel.sleep(PASSO_DA_ESPERA) while ocupada?(chave) && Time.current < limite
  end

  def ocupada?(chave)
    ::Redis::Alfred.exists?(chave)
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][envio_em_ordem] redis indisponível #{e.class}")
    false
  end

  def travar(chave, token)
    ::Redis::Alfred.set(chave, token, nx: true, ex: TTL)
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][envio_em_ordem] redis indisponível #{e.class}")
    false
  end

  def soltar(chave, token)
    ::Redis::Alfred.delete_if_equals(chave, token)
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][envio_em_ordem] trava não solta #{e.class}")
  end
end
