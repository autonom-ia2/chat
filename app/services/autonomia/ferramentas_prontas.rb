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
  # AS RODADAS DE FERRAMENTA POR RESPOSTA (#2918, decisão do Rodrigo em 11/11/2026): as do Experimente da vitrine
  # (`Experimente::ComModelo::MAX_RODADAS` aponta para cá) e as do agente com pronta no atendimento. Uma constante só, para
  # o que o dono vê no teste não voltar a ser melhor do que o cliente recebe: com uma rodada, a NCM "café torrado" parava
  # no grupo 0901.2, e o código da nota só vinha na segunda consulta.
  RODADAS_POR_RESPOSTA = 3
  # O PRAZO DAS RODADAS no atendimento: o relógio não corta nenhuma, na mesma conta da Lia
  # (`QuoteAgent::Builder.rodadas_do_turno`: rodadas × a espera de uma rodada inteira). Uma rodada inteira é uma ida ao
  # modelo no teto dela (`ResponsesClient::REQUEST_TIMEOUT`) e a janela da consulta no turno
  # (`ConsultaNoTurno::ESPERA_DO_TURNO`, 8 s). O `ResponsesClient` só confere o relógio antes de abrir as rodadas 2 e 3, e
  # nenhuma rodada normal chega perto disto; ele só pesa com a OpenAI degradada (as novas tentativas) ou numa fonte lenta
  # no caminho síncrono (o `prazo_total` dela, até 12 s). O que limita é a rodada (três) e o prazo de cada consulta: um
  # relógio curto cortaria a segunda consulta quando o modelo demora, e o agente voltaria a responder pela metade, sem
  # aviso. Não vale o `MAX_SEGUNDOS` do Experimente: ele existe pelo corte de 15 s do pedido web; o atendimento roda no
  # `ReplyJob`. Constante lida no corpo do módulo: `ConsultaNoTurno` não pode ler constante daqui no corpo da classe dele.
  PRAZO_DAS_RODADAS = RODADAS_POR_RESPOSTA *
                      (Crm::Ai::ResponsesClient::REQUEST_TIMEOUT + Autonomia::Agents::Tools::ConsultaNoTurno::ESPERA_DO_TURNO)

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

  # As liberadas que a conta vê na vitrine e nas sugestões: fora as de uso interno (`Fonte#na_vitrine?` falso).
  def da_vitrine(account)
    disponiveis(account).select(&:na_vitrine?)
  end

  # A fonte pode ser oferecida e incluída pela vitrine (o "Incluir", o Experimente, a sugestão e o Construtor).
  def na_vitrine?(account, fonte)
    disponivel?(account, fonte) && fonte.na_vitrine?
  end

  # A ferramenta entra no turno deste agente? A cadastrada, sempre; a pronta, só com a flag, fora da Lia e com a fonte
  # ainda no catálogo (uma fonte que saiu do código não derruba o turno de quem a tinha). A que saiu da vitrine continua.
  def no_turno?(tool, agent)
    return true unless tool.pronta?

    disponivel?(agent.account, tool.fonte_do_catalogo) && agent.agent_type != AGENTE_DE_COTACAO
  end

  # As rodadas do agente que RECEBE ao menos uma pronta no turno (`no_turno?`: a flag das prontas e a da fonte ligadas na
  # conta dele, fora da Lia). -> kwargs para o `Answerer`, ou nil (vale o padrão de quem chama). Sem a flag das prontas,
  # nem consulta o banco. O Rodrigo autorizou CONSULTAR até 3 vezes, não escrever: a ferramenta que escreve roda uma vez
  # por turno (`uma_escrita_por_turno`, `Tools::UmaEscritaPorTurno`); a leitura segue livre.
  def rodadas(agent)
    return nil if agent.blank? || agent.agent_type == AGENTE_DE_COTACAO || !ligada?(agent.account)
    return nil unless agent.tools.enabled.where.not(fonte_pronta: nil).any? { |tool| tool.pronta? && no_turno?(tool, agent) }

    { max_rodadas: RODADAS_POR_RESPOSTA, max_segundos: PRAZO_DAS_RODADAS, uma_escrita_por_turno: true }
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
