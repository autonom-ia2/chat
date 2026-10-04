# Quantas vezes cada regra de automação disparou, por hora (#935).
#
# Uma regra disparando 40 vezes num dia só aparecia quando já tinha virado prejuízo. Aqui fica a
# contagem: um contador no Redis por regra e por hora, que some sozinho em 48 h. Só número — nada da
# conversa nem da mensagem que fez a regra disparar.
#
# O JSON da regra traz `disparos: { hora:, ultimas_24h: }`, e a vigia do Guia mede por ele.
module AutomationRules::Disparos
  VALIDADE = 48.hours.to_i
  HORAS_NO_DIA = 24

  module_function

  def registrar(rule_id)
    chave = chave(rule_id, Time.current)
    Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, VALIDADE)
  rescue StandardError => e
    # Contar nunca pode impedir a regra de rodar.
    Rails.logger.warn("[automation_rules][disparos] regra=#{rule_id} #{e.class}: #{e.message}")
  end

  def de(rule_id)
    agora = Time.current
    chaves = Array.new(HORAS_NO_DIA) { |atras| chave(rule_id, agora - atras.hours) }
    contagens = Redis::Alfred.with { |conexao| conexao.mget(*chaves) }.map(&:to_i)
    { hora: contagens.first, ultimas_24h: contagens.sum }
  end

  def chave(rule_id, momento)
    "automation_rule:disparos:#{rule_id}:#{momento.utc.strftime('%Y%m%d%H')}"
  end
end
