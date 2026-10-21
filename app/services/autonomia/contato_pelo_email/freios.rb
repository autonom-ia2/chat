# Contato pelo e-mail recebido (#1813): os freios de custo e de corrida, todos no Redis, por contato e por conta.
#
# - Pausa: o contato fica um tempo sem passar pela IA. 30 dias depois de 3 leituras `automatico` SEGUIDAS (a
#   newsletter que chega toda semana não paga a IA toda semana); 24 horas quando a IA leu e nada mudou no contato. A
#   pausa vale para o e-mail que chegou depois dela: o que já estava na fila (esperando a trava, por exemplo) é lido,
#   porque pode ser justamente o que traz o telefone.
# - Contador de automáticos: zera numa leitura `pessoa` ou `formulario`; expira sozinho.
# - Trava: uma leitura por contato de cada vez (dois e-mails seguidos não pagam duas leituras que gravam por cima).
# - Leitura única por mensagem: a nova tentativa do job não paga a IA de novo pelo mesmo e-mail.
# - Teto diário de chamadas por conta e, quando a IA é paga pela chave da instalação, também um teto da instalação
#   inteira (o teto por conta sozinho deixaria N contas x 5000 chamadas por dia na mesma chave).
class Autonomia::ContatoPeloEmail::Freios
  PREFIXO = 'autonomia:contato_pelo_email'.freeze
  AUTOMATICOS_PARA_PAUSAR = 3
  AUTOMATICOS_POR = 30.days
  PAUSA_AUTOMATICOS = 30.days
  PAUSA_NADA_NOVO = 24.hours
  TETO_DIARIO = 5000
  TETO_DIARIO_DA_INSTALACAO = 20_000
  TRAVA_POR = 5.minutes
  LIDO_POR = 1.day
  SEPARADOR = ':'.freeze

  def initialize(account_id:, contato_id:)
    @account_id = account_id
    @contato_id = contato_id
  end

  # O e-mail que chegou em `chegou_em` cai na pausa? Só quando chegou depois de ela começar.
  def pausado?(chegou_em)
    valor = Redis::Alfred.get(chave('pausa', @contato_id))
    return false if valor.nil?

    chegou_em.to_i >= valor.to_s.split(SEPARADOR).last.to_i
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

  # Conta mais uma chamada da conta hoje (UTC) e, com a chave da instalação, mais uma da instalação.
  # -> false quando passou de algum dos tetos.
  def dentro_do_teto?(chave_da_instalacao: false)
    dia = Time.now.utc.to_date.iso8601
    return false if contar(chave('teto', "#{@account_id}:#{dia}"), 1.day + 1.hour) > TETO_DIARIO
    return true unless chave_da_instalacao

    contar(chave('teto_instalacao', dia), 1.day + 1.hour) <= TETO_DIARIO_DA_INSTALACAO
  end

  private

  # O prazo nasce junto com a chave (SET NX EX) e o INCR o mantém, os dois numa transação (MULTI): nenhum contador fica
  # sem expirar, nem se o processo cair entre os dois, nem se a chave expirar entre eles.
  def contar(contador, prazo)
    Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.set(contador, 0, nx: true, ex: prazo.to_i)
        transacao.incr(contador)
      end.last
    end
  end

  # Guarda o motivo e o começo da pausa (segundos), para #pausado? saber quais e-mails chegaram antes dela. Nunca
  # encurta a pausa que já está valendo: o "nada novo" (24 h) de uma leitura que pegou a trava logo depois da pausa de
  # 30 dias dos automáticos não pode trocá-la.
  def pausar(tempo, motivo)
    return if Redis::Alfred.ttl(chave('pausa', @contato_id)).to_i > tempo.to_i

    Redis::Alfred.setex(chave('pausa', @contato_id), [motivo, Time.current.to_i].join(SEPARADOR), tempo.to_i)
  end

  def chave(tipo, id)
    "#{PREFIXO}:#{tipo}:#{id}"
  end
end
