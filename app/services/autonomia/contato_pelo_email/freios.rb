# Contato pelo e-mail recebido (#1813): os freios de custo e de corrida, todos no Redis, por contato e por conta.
#
# - Pausa: o contato fica um tempo sem passar pela IA. 30 dias depois de 3 leituras `automatico` SEGUIDAS (a
#   newsletter que chega toda semana não paga a IA toda semana); 7 dias quando a IA leu e nada foi gravado.
# - Contador de automáticos: zera numa leitura `pessoa` ou `formulario`; expira sozinho.
# - Trava: uma leitura por contato de cada vez (dois e-mails seguidos não pagam duas leituras que gravam por cima).
# - Leitura única por mensagem: a nova tentativa do job não paga a IA de novo pelo mesmo e-mail.
# - Teto diário de chamadas por conta.
class Autonomia::ContatoPeloEmail::Freios
  PREFIXO = 'autonomia:contato_pelo_email'.freeze
  AUTOMATICOS_PARA_PAUSAR = 3
  AUTOMATICOS_POR = 30.days
  PAUSA_AUTOMATICOS = 30.days
  PAUSA_NADA_NOVO = 7.days
  TETO_DIARIO = 500
  TRAVA_POR = 5.minutes
  LIDO_POR = 1.day

  def initialize(account_id:, contato_id:)
    @account_id = account_id
    @contato_id = contato_id
  end

  def pausado?
    Redis::Alfred.exists?(chave('pausa', @contato_id))
  end

  def pausar_por_nada_novo
    pausar(PAUSA_NADA_NOVO, 'nada_novo')
  end

  # Mais uma leitura automática seguida; na terceira, a pausa de 30 dias. -> true quando pausou.
  def automatico!
    contador = chave('automaticos', @contato_id)
    return false if contar(contador, AUTOMATICOS_POR) < AUTOMATICOS_PARA_PAUSAR

    pausar(PAUSA_AUTOMATICOS, 'automatico')
    Redis::Alfred.delete(contador)
    true
  end

  def zerar_automaticos
    Redis::Alfred.delete(chave('automaticos', @contato_id))
  end

  # -> o token da trava, ou nil quando outra leitura do mesmo contato está em andamento.
  def travar
    token = SecureRandom.hex(8)
    Redis::Alfred.set(chave('trava', @contato_id), token, nx: true, ex: TRAVA_POR.to_i) ? token : nil
  end

  def soltar(token)
    Redis::Alfred.delete_if_equals(chave('trava', @contato_id), token)
  end

  # true só na primeira vez para esta mensagem.
  def primeira_leitura?(message_id)
    Redis::Alfred.set(chave('lido', message_id), 1, nx: true, ex: LIDO_POR.to_i) ? true : false
  end

  # Conta mais uma chamada da conta hoje (UTC). -> false quando passou do teto.
  def dentro_do_teto?
    chave_do_dia = chave('teto', "#{@account_id}:#{Time.now.utc.to_date.iso8601}")
    contar(chave_do_dia, 1.day + 1.hour) <= TETO_DIARIO
  end

  private

  # O prazo nasce junto com a chave (SET NX EX) e o INCR o mantém: nenhum contador fica sem expirar se o processo cair
  # entre os dois comandos.
  def contar(contador, prazo)
    Redis::Alfred.set(contador, 0, nx: true, ex: prazo.to_i)
    Redis::Alfred.incr(contador)
  end

  def pausar(tempo, motivo)
    Redis::Alfred.setex(chave('pausa', @contato_id), motivo, tempo.to_i)
  end

  def chave(tipo, id)
    "#{PREFIXO}:#{tipo}:#{id}"
  end
end
