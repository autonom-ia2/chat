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
  AGENTE_DE_COTACAO = 'insurance_quote'.freeze

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # A ferramenta entra no turno deste agente? A cadastrada, sempre; a pronta, só com a flag, fora da Lia e com a fonte
  # ainda no catálogo (uma fonte que saiu do código não derruba o turno de quem a tinha).
  def no_turno?(tool, agent)
    return true unless tool.pronta?

    tool.fonte_do_catalogo.present? && ligada?(agent.account) && agent.agent_type != AGENTE_DE_COTACAO
  end

  # Quem executa a chamada: a `Execucao` para a pronta, o `HttpExecutor` para a cadastrada. As opções do `HttpExecutor`
  # (`turno`, `segundos`, `chave`, `higienizar`) não valem para a pronta: ela não manda cabeçalho nem chave a ninguém, e
  # o prazo dela é o do catálogo.
  def executor_para(tool, params:, **opcoes)
    return Execucao.new(tool: tool, params: params) if tool.pronta?

    ::Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: params, **opcoes)
  end
end
