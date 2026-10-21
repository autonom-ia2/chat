# F3 do tema 8 (#1429): o que uma comparação pronta deixa guardado no Redis.
# - Quem viu: a versão da base nova que cada pessoa (account_user) comparou neste agente, por 30 minutos. O "atualizar"
#   só grava a versão que a própria pessoa viu comparada: nem o Guia nem a API trocam a base sem o antes e depois. Vale
#   para uma troca só (esquecer_quem_viu! depois de trocar).
# - O resultado: o antes e depois do agente para aquela versão, no idioma em que foi feito, pelos mesmos 2 minutos da
#   espera entre comparações. Reabrir a gaveta nesse intervalo mostra o mesmo antes e depois em vez de mandar esperar.
#
# Os dois valem para o agente como ele estava ao comparar (o RETRATO: a instrução e a versão da base de hoje). Mudou a
# instrução (edição, volta de versão) ou a base (atualizar e Desfazer), o "hoje" comparado não é mais o de agora: a marca
# não vale e o resultado guardado não serve. Não usa o updated_at, que muda por motivos que não mexem na resposta.
module Autonomia::Agents::BaseDeSeguros::Comparada
  PRAZO_DE_QUEM_VIU = 30.minutes
  PREFIXO = 'autonomia:base_de_seguros:comparada'.freeze

  module_function

  def guardar!(agent, account_user, idioma, resultado)
    versao = resultado.with_indifferent_access[:versao]
    Redis::Alfred.set(chave_do_resultado(agent, versao, idioma), resultado.to_json,
                      ex: Autonomia::Agents::BaseDeSeguros::Limite::ENTRE_PEDIDOS.to_i)
    marcar_quem_viu!(agent, account_user, versao)
  end

  def marcar_quem_viu!(agent, account_user, versao)
    Redis::Alfred.set(chave_de_quem_viu(agent, account_user), marca(agent, versao), ex: PRAZO_DE_QUEM_VIU.to_i)
  end

  def viu?(agent, account_user, versao)
    return false if account_user.nil? || versao.blank?

    Redis::Alfred.get(chave_de_quem_viu(agent, account_user)) == marca(agent, versao)
  end

  def esquecer_quem_viu!(agent, account_user)
    Redis::Alfred.delete(chave_de_quem_viu(agent, account_user)) if account_user
  end

  # O antes e depois guardado (chaves em texto, como sai do job), ou nil.
  def resultado(agent, versao, idioma)
    guardado = Redis::Alfred.get(chave_do_resultado(agent, versao, idioma))
    JSON.parse(guardado) if guardado
  end

  # O agente como ele responde hoje, para o que muda a resposta da comparação: a instrução e a versão da base gravada.
  def retrato(agent)
    base = agent.config.to_h['base']
    versao_da_base = base.is_a?(Hash) ? base['versao'] : nil
    Digest::SHA256.hexdigest([agent.instruction.to_s, versao_da_base.to_s].to_json)[0, 16]
  end

  def marca(agent, versao)
    "#{versao}:#{retrato(agent)}"
  end

  def chave_de_quem_viu(agent, account_user)
    "#{PREFIXO}:viu:agente:#{agent.id}:pessoa:#{account_user.id}"
  end

  def chave_do_resultado(agent, versao, idioma)
    "#{PREFIXO}:resultado:agente:#{agent.id}:#{versao}:#{retrato(agent)}:#{idioma}"
  end
end
