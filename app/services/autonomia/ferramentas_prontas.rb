# FERRAMENTAS PRONTAS (#2858): o agente consulta uma fonte pública do catálogo com um toque, sem link digitado.
#
# A ferramenta pronta é uma linha de `autonomia_agent_tools` com `fonte_pronta` (a chave da fonte no `Catalogo`). Ela
# passa pelo mesmo caminho da ferramenta HTTP cadastrada — o turno (`Tools::Bound`) e a consulta em segundo plano do
# #2749 (`ConsultaNoTurno`, `HttpAssincronaJob`), que acham a ferramenta pelo id —, e só o executor muda: em vez do
# `HttpExecutor` (o link da conta), a `Execucao` (a fonte do catálogo, com reserva, cache, contador e limite).
#
# A flag `agente_ferramentas_prontas` desligada tira as prontas do turno e recusa o "Incluir": a conta volta ao que
# era. A Lia (`insurance_quote`) fica de fora: as ferramentas dela são as do deploy.
module Autonomia::FerramentasProntas
  FLAG = 'agente_ferramentas_prontas'.freeze
  # A F1 (#2858): as consultas mais usadas além de CEP, CNPJ e FIPE (CPF, feriados, Banco Central, cidades, DDD,
  # localização, bancos). Vale junto com a FLAG.
  FLAG_CONSULTAS = 'agente_ferramentas_prontas_consultas'.freeze
  # A F2 (#2858): a vitrine (a tela e a API dela). Vale junto com a FLAG.
  FLAG_VITRINE = 'agente_ferramentas_prontas_vitrine'.freeze
  # A F3 (#2858): o Construtor escolhe as prontas do agente novo, e o agente que já existe recebe a sugestão. Vale junto
  # com a vitrine: quem inclui é o mesmo endpoint dela.
  FLAG_CONSTRUTOR = 'agente_ferramentas_prontas_construtor'.freeze
  AGENTE_DE_COTACAO = 'insurance_quote'.freeze

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def vitrine?(account)
    ligada?(account) && account.feature_enabled?(FLAG_VITRINE)
  end

  def construtor?(account)
    vitrine?(account) && account.feature_enabled?(FLAG_CONSTRUTOR)
  end

  # As fontes do catálogo liberadas para a conta, na ordem do catálogo.
  def disponiveis(account)
    Catalogo.todas.select { |fonte| disponivel?(account, fonte) }
  end

  # A fonte está liberada para a conta: a flag das prontas e, na fonte de uma fase posterior, a flag dela.
  def disponivel?(account, fonte)
    fonte.present? && ligada?(account) && (fonte.flag.nil? || account.feature_enabled?(fonte.flag))
  end

  # A ferramenta entra no turno deste agente? A cadastrada, sempre; a pronta, só com a flag, fora da Lia e com a fonte
  # ainda no catálogo (uma fonte que saiu do código não derruba o turno de quem a tinha).
  def no_turno?(tool, agent)
    return true unless tool.pronta?

    disponivel?(agent.account, tool.fonte_do_catalogo) && agent.agent_type != AGENTE_DE_COTACAO
  end

  # A pronta calculada aqui (o CPF: nenhum host) não vai ao caminho em segundo plano do #2749 (`ConsultaNoTurno.aplica?`):
  # responde na hora e não abre a linha da consulta, que guardaria o argumento.
  def calculada_aqui?(tool)
    tool.pronta? && tool.fonte_do_catalogo.present? && tool.fonte_do_catalogo.hosts.empty?
  end

  # Os argumentos da pronta já normalizados, antes de qualquer registro (a linha da consulta em segundo plano grava os
  # argumentos): a coordenada vai arredondada, o documento só com os dígitos, e o que não normaliza vira
  # `Fonte::FORA_DO_FORMATO` (a `Execucao` responde que o pedido não serve). A cadastrada: como veio.
  def argumentos(tool, args)
    fonte = tool.pronta? ? tool.fonte_do_catalogo : nil
    return args if fonte.nil? || !args.is_a?(Hash)

    fonte.normalizar_argumentos(args.deep_stringify_keys)
  end

  # Quem executa a chamada: a `Execucao` para a pronta, o `HttpExecutor` para a cadastrada. As opções do `HttpExecutor`
  # (`turno`, `segundos`, `chave`, `higienizar`) não valem para a pronta: ela não manda cabeçalho nem chave a ninguém, e
  # o prazo dela é o do catálogo.
  def executor_para(tool, params:, **opcoes)
    return Execucao.new(tool: tool, params: params) if tool.pronta?

    ::Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: params, **opcoes)
  end
end
