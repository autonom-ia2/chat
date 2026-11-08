# F3 do tema 8 (#1429): o que uma comparação pronta deixa guardado no Redis.
# - Quem viu: a versão da base nova que cada pessoa (account_user) comparou neste agente, por 30 minutos. O "atualizar"
#   só grava a versão que a própria pessoa viu comparada: nem o Guia nem a API trocam a base sem o antes e depois. Vale
#   para uma troca só (esquecer_quem_viu! depois de trocar).
# - O resultado: o antes e depois do agente para aquela versão, no idioma em que foi feito, pelos mesmos 2 minutos da
#   espera entre comparações. Reabrir a gaveta nesse intervalo mostra o mesmo antes e depois em vez de mandar esperar.
#
# Os dois valem para o agente como ele estava ao comparar (o RETRATO: o mesmo da versão do agente, com a instrução, o
# jeito de falar, as regras de passagem, a mensagem de quando não sabe, a config versionada e a base). Mudou qualquer um
# (edição, volta de versão, atualizar e Desfazer), o "hoje" comparado não é mais o de agora: a marca não vale e o
# resultado guardado não serve. O limite de confiança saiu (tema 6, #1428): a comparação roda como o atendimento, sem
# o portão, e o limite deixou de ser do agente.
#
# FICA FORA, por não mudar a resposta da comparação (o caminho do Testar em modo prova, sem ferramenta):
# - model e temperature: o Answerer usa o modelo fixo dele (Config::ANSWERER_MODEL) e não passa temperatura;
# - handoff_strategy/handoff_target_id: dizem para QUEM vai a conversa, não o que o agente responde;
# - business_hours, response_window, audience: dizem QUANDO e PARA QUEM ele atende, não o texto;
# - topic_map, knowledge_summary, knowledge_confidence, o material e os ajudantes: o sistema reescreve o material e o
#   resumo sozinho (entrariam como falso "compare de novo"), e os ajudantes só entram com ferramenta, que a prova não usa;
# - ligar, desligar e o updated_at: mudam por motivos que não mexem na resposta.
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

  # O agente como ele responde hoje (TrocaDaBase#retrato_para_comparar: o retrato da versão com a instrução).
  def retrato(agent)
    agent.retrato_para_comparar
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
