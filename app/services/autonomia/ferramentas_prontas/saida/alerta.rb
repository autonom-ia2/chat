# Alerta operacional da saída das consultas grátis (#2942): fatia vazia ou quase, IP da fatia fora da reservada, IP
# sumido, quarentena, Webshare fora, consulta sem IP próprio. Problema da PLATAFORMA (comprar IP, ajustar a fatia), nunca
# do cliente. Log `[autonomia][pronta][saida][alerta]` e Sentry (quando a instalação tem SENTRY_DSN), no máximo um por
# código e assunto por hora; com o Redis fora, todos passam. Nunca leva credencial; IP só mascarado.
module Autonomia::FerramentasProntas::Saida::Alerta
  JANELA = 1.hour.to_i
  CHAVE = 'autonomia:prontas:saida:alerta'.freeze

  module_function

  def avisar!(codigo, mensagem, nivel: :warning, assunto: nil)
    return unless primeiro_na_janela?(codigo, assunto)

    Rails.logger.public_send(nivel == :error ? :error : :warn, "[autonomia][pronta][saida][alerta] #{codigo}: #{mensagem}")
    para_o_sentry(codigo, mensagem, nivel)
  end

  def primeiro_na_janela?(codigo, assunto)
    Redis::Alfred.set([CHAVE, codigo, assunto].compact.join(':'), '1', nx: true, ex: JANELA) ? true : false
  rescue *Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS
    true
  end

  def para_o_sentry(codigo, mensagem, nivel)
    return if ENV['SENTRY_DSN'].blank? || !defined?(Sentry)

    Sentry.capture_message("[autonomia][pronta][saida] #{codigo}: #{mensagem}",
                           level: nivel, fingerprint: ['autonomia_prontas_saida', codigo])
  end
end
