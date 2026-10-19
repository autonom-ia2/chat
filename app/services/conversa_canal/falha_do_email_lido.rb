# Registro de falha do "lido" do e-mail sincronizado (#1870).
# - O erro do IMAP ou do OAuth carrega texto do provedor (resposta do servidor, corpo do OAuth); nada disso sai daqui. O
#   log e o ChatwootExceptionTracker recebem só a classe do erro original, embrulhada nesta exceção.
# - Ao rastreador vai só a primeira falha de cada caixa na JANELA (chave no Redis com TTL); as outras ficam só no log.
#   Caixa com o servidor fora do ar não inunda o rastreador.
class ConversaCanal::FalhaDoEmailLido < StandardError
  JANELA = 1.hour

  def self.registrar(error, account:, inbox_id:, onde:, rastrear: true)
    Rails.logger.info("[conversa_canal][email_lido] #{onde} falhou #{error.class}")
    return unless rastrear && primeira_da_janela?(inbox_id)

    ChatwootExceptionTracker.new(new(error.class.name), account: account).capture_exception
  end

  def self.primeira_da_janela?(inbox_id)
    Redis::Alfred.set("conversa_canal:email_lido:falha_rastreada:#{inbox_id}", '1', nx: true, ex: JANELA.to_i)
  end
end
