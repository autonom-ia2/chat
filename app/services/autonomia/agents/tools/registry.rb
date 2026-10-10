# Catálogo das ferramentas NATIVAS disponíveis na instalação (#312).
#
# Nativa é declarada em código, não no banco: quem decide que ela existe somos nós; o dono da conta
# só decide se liga (`agent.config['native_tool_slugs']`), menos no Agente de Cotação, cuja lista é a do
# deploy e ignora a config (`Agent#ferramentas_nativas`, fatia 2 do #420). Isso é deliberado — a
# ferramenta nativa carrega credencial e assinatura, então a superfície precisa ser fechada.
module Autonomia::Agents::Tools::Registry
  # Ordem estável: entra no prompt nesta ordem quando o agente liga várias.
  # CADA FERRAMENTA PERTENCE A UM FLUXO (#1211), e a lista é a do fluxo: `permitidas_para`.
  DE_ATENDIMENTO = [
    # Ordem é a da jornada: o que a corretora cota, cotar, e o que o contrato diz.
    Autonomia::Agents::Tools::Native::InsuranceCapabilities,
    # UMA ferramenta para os onze ramos. Havia duas — uma só de auto, com os campos digitados à
    # mão, e outra para o resto —, e a separação custava caro: o comparativo em PDF e o registro da
    # seguradora que recusou a credencial da corretora ficavam de fora dos outros dez, e nenhum dos
    # dois é de auto. Auto é um ramo com UM comportamento extra, o bônus de renovação.
    Autonomia::Agents::Tools::Native::InsuranceQuote,
    # A consulta do principal ao resultado que a cotação guardou (fatia 2 do #420): lê o banco, não cota.
    Autonomia::Agents::Tools::Native::InsuranceQuoteResult,
    # A proposta de uma seguradora só, em PDF, sobre a mesma cotação (entrega 8b, #459): não cota.
    Autonomia::Agents::Tools::Native::InsuranceQuoteProposal,
    Autonomia::Agents::Tools::Native::VehicleLookup,
    # A consulta de CEP do imóvel (autonomia-adapters#87): no catálogo desde já, e só o especialista de
    # ramo com imóvel a recebe (`QuoteAgent::Builder::CONSULTAS_DO_RAMO`).
    Autonomia::Agents::Tools::Native::CepLookup,
    Autonomia::Agents::Tools::Native::AtividadeLookup,
    Autonomia::Agents::Tools::Native::InsuranceGeneralConditions,
    # #1196 — a agenda da IA: ligadas ao escolher a página de agendamento do agente (`config['booking_page_id']`).
    Autonomia::Agents::Tools::Native::HorariosDisponiveis,
    Autonomia::Agents::Tools::Native::AgendarReuniao
  ].freeze

  DO_GUIA = [
    # Guia da Plataforma (#568, #590): ler a conta, propor mudança nela e levar
    # a pessoa até a tela, com a permissão de quem está logado. Ligadas só no
    # agente do Guia, que o `Seed` semeia — nenhum agente de conta as enxerga
    # (`permitidas_para`, que a API e o catálogo do turno consultam).
    Autonomia::Agents::Tools::Native::GuiaLeitura,
    Autonomia::Agents::Tools::Native::GuiaAcao,
    # #855 — o Guia executa o que tem desfazer, passo a passo, no mesmo turno.
    Autonomia::Agents::Tools::Native::GuiaExecucao,
    # #900 — o formato de uma ação, gerado do código, para o corpo sair certo de primeira.
    Autonomia::Agents::Tools::Native::GuiaFormato,
    # #857 — o Guia lê uma página da internet quando a busca não basta.
    Autonomia::Agents::Tools::Native::GuiaPagina,
    # #857 — o Guia lê o conteúdo de um anexo de conversa (documento, áudio, imagem).
    Autonomia::Agents::Tools::Native::GuiaAnexo,
    Autonomia::Agents::Tools::Native::GuiaTela,
    # A Central de Ajuda (#617): o passo a passo escrito para a própria
    # pessoa, na língua da tela — melhor fonte que o manual interno para
    # "como eu faço X".
    Autonomia::Agents::Tools::Native::GuiaCentral,
    # #858 — o Guia classifica muitos itens de uma vez com o Jev ("desses contatos, quais…").
    Autonomia::Agents::Tools::Native::GuiaClassificar,
    # #933 — o Guia anota e esquece o que a pessoa ensinou, entre conversas.
    Autonomia::Agents::Tools::Native::GuiaLembrar,
    Autonomia::Agents::Tools::Native::GuiaEsquecer,
    # #936 — o Guia planeja um trabalho grande: receita, amostra e o botão Começar para a pessoa.
    Autonomia::Agents::Tools::Native::GuiaTarefa
  ].freeze

  TOOLS = (DE_ATENDIMENTO + DO_GUIA).freeze

  module_function

  def all
    TOOLS
  end

  def find(slug)
    TOOLS.find { |tool| tool.slug == slug.to_s }
  end

  def slugs
    TOOLS.map(&:slug)
  end

  # A LISTA PERMITIDA É A DO FLUXO DO AGENTE (#1211). O Guia da Plataforma é o agente de sistema que o
  # `Guide::Seed` semeia (`system_key`, que a API nunca aceita do cliente); todo o resto é atendimento.
  # Antes disto a API gravava em `native_tool_slugs` qualquer slug do catálogo, e quem editava um agente
  # comum ligava nele as ferramentas do Guia.
  def permitidas_para(agent)
    do_guia?(agent) ? DO_GUIA : DE_ATENDIMENTO
  end

  def do_guia?(agent)
    agent.config.to_h['system_key'] == ::Autonomia::Guide::Seed::SYSTEM_KEY
  end

  # Ferramentas realmente utilizáveis por este agente: ligadas (`Agent#ferramentas_nativas`: a lista do
  # deploy para o Agente de Cotação, a config para os demais), DO FLUXO DELE (`permitidas_para` — um slug
  # de outro fluxo já gravado no banco não chega ao modelo) E disponíveis (o gate `available_for?` evita
  # oferecer no prompt algo que vai falhar por falta de configuração).
  def for_agent(agent)
    enabled = Array(agent.ferramentas_nativas).map(&:to_s)
    return [] if enabled.empty?

    permitidas = permitidas_para(agent)
    enabled.filter_map { |slug| find(slug) }.uniq.select { |tool| permitidas.include?(tool) && tool.available_for?(agent) }
  end
end
