# AS LISTAS DO MODELO PRONTO NAS INSTRUÇÕES DO AGENTE QUE ATENDE (#2881). Texto montado pelo servidor, a cada turno, a
# partir da marca do agente (`config['modelo_pronto']`): as perguntas da cotação e os documentos como o dono os deixou.
# É por isso que tirar, editar ou incluir um item não pede nova chamada (paga) ao Construtor: a instrução que ele
# escreveu fala em "perguntas da cotação" e "documentos", e a lista em si chega por aqui.
#
# Entra logo depois da instrução do agente (`PromptBuilder#instructions`), como a instrução da agenda. Sem a marca
# (todo agente que não nasceu de um modelo), nil: as instruções ficam byte a byte as de antes. Lê só a marca, nunca a
# flag nem o arquivo do modelo: nada muda sozinho um agente que já existe (o mesmo princípio da marca de base, #1429).
# A Lia e os agentes de sistema ficam de fora.
module Autonomia::Agents::ModelosDeRamo::Instrucao
  TITULO = '# Perguntas da cotação e documentos (listas atuais)'.freeze
  REGRA = 'As duas listas abaixo são as que valem agora. Quando estas instruções falarem em perguntas da cotação ou em ' \
          'documentos, use estas listas. Se outro trecho citar uma pergunta ou um documento que não está aqui, não peça.'.freeze

  module_function

  def do_agente(agent)
    config = agent.config.to_h
    marca = config[Autonomia::Agents::ModelosDeRamo::Marca::CHAVE]
    return unless marca.is_a?(Hash)
    return if config['system_key'].present? || agent.agent_type == Autonomia::Agents::ModelosDeRamo::AGENTE_DE_COTACAO

    listas = Autonomia::Agents::ModelosDeRamo::Marca
    [TITULO, REGRA, "PERGUNTAS DA COTAÇÃO:\n#{listas.numerada(marca, 'perguntas')}",
     "DOCUMENTOS:\n#{listas.numerada(marca, 'documentos')}"].join("\n\n")
  end
end
