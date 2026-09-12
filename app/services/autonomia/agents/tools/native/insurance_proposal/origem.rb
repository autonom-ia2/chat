# DE QUAL COTAÇÃO A PROPOSTA SAI — e quando ela NÃO pode sair (entrega 8, rodadas de correção).
#
# A ORIGEM É ESCOLHIDA UMA VEZ, NO ACEITE, E FIXADA; E SÓ VALE ENQUANTO FOR A ÚLTIMA COTAÇÃO DA
# CONVERSA. Até 12/09/2026 `precheck` e `start` procuravam, cada um por si, "a última cotação com
# preço desta conversa" — inclusive uma já supersedida. O cenário (Codex, P1): a cotação A entregou
# preços, o cliente corrigiu o veículo e abriu B; "me manda a da Porto" durante B gerava a proposta
# de A — o risco errado, com cara de certo. Agora:
#   - NO TURNO (há `delivery`), a origem é ESCOLHIDA: a última cotação desta conversa com preço
#     entregue e com o mapa de nomes, VIVA ou ENCERRADA — nunca morta (`ToolRun#dead?`). O aceite a
#     grava nos ARGUMENTOS da execução (`Native::Base#argumentos`, chave `ORIGEM`);
#   - NO JOB (sem `delivery`), a origem é a FIXADA, e só ela: `start` a lê dos argumentos, `poll` do
#     handle (o `start` a copia);
#   - EM TODOS OS MOMENTOS — turno, `start`, cada passada do `poll`, o encerramento por prazo
#     (`closing_deliveries`) e a PUBLICAÇÃO EFETIVA (`publicavel?`, que pode sair até 90 s depois da
#     passada que produziu o arquivo) — a pergunta é UMA: a origem ainda é a ÚLTIMA cotação desta
#     conversa, e não está morta? Se não for, `cotacao_substituida`, sem portal e sem entrega.
#
# A REGRA DA ÚLTIMA (rodada 4: os dois P1 do Codex e o R7). As versões anteriores descreviam a mesma
# coisa com DOIS predicados — `dead?` mais "há uma cotação nova VIVA e ainda sem preço" — e cada uma
# deixava um buraco, porque uma cotação `done` NUNCA vira `superseded` (`ToolRun.open!` só supersede
# a viva):
#   (a) `dead?` sozinho não pegava a origem `done` com outra cotação aberta depois;
#   (b) "nova viva sem preço" voltava a AUTORIZAR a origem antiga no instante em que a nova recebia
#       preço — o cliente podia receber o PDF de A depois de já estar lendo os preços de B;
#   (c) recotação que morre sem preço (`failed`) não barrava nada, e o anexo da lista antiga saía sem
#       uma palavra ao cliente (R7, reproduzido pelo verificador cego).
# Se o cliente abriu outra cotação depois, o estado dela não importa — viva, com preço, encerrada ou
# falhada: a lista que vale é a nova, e a proposta da anterior não sai. Um predicado, um motivo.
module Autonomia::Agents::Tools::Native::InsuranceProposal::Origem
  extend ActiveSupport::Concern

  # A chave da cotação de origem: nos ARGUMENTOS da execução (gravada pelo aceite) e no HANDLE
  # (copiada pelo `start`, lida pelo `poll`). É o id da linha da cotação em `autonomia_agent_tool_runs`.
  ORIGEM = 'cotacao_run_id'.freeze
  # As cotações que NUNCA viraram trabalho, e por isso não contam como "o cliente mandou refazer":
  # a `pending` órfã (o worker morreu entre o aceite e o despacho — um deploy basta —, e a linha fica
  # parada até o prazo, até uma hora), a descartada com o turno e a barrada pelo gate da conta.
  # Nenhuma delas vai trazer preço novo, e contá-las travaria a proposta por uma cotação que ninguém
  # vai executar. É a MESMA lista de `ToolRun.opened_for_turn?`, pelo mesmo motivo (verificador cego,
  # I2 da rodada 3).
  SEM_TRABALHO = %w[pending discarded blocked].freeze

  # O que o aceite grava como argumentos (`Native::Base#argumentos`): o que o modelo escreveu MAIS a
  # cotação de origem escolhida agora. Sem cotação não há o que fixar — e a conferência já recusou.
  def argumentos
    origem = cotacao
    origem ? params.merge(ORIGEM => origem.id) : params
  end

  private

  # A cotação de origem: ESCOLHIDA no turno, FIXADA no job (ver o cabeçalho). nil quando não há.
  def cotacao
    return @cotacao if defined?(@cotacao)

    @cotacao = delivery ? escolher_cotacao : cotacao_fixada(params[ORIGEM])
  end

  # O `poll` fixa a origem pelo handle: é o mesmo id que o `start` leu dos argumentos e copiou.
  def fixar_origem(id)
    @cotacao = cotacao_fixada(id)
  end

  # A mais recente por id entre as que têm preço e mapa, e NÃO estão mortas: uma cotação supersedida
  # é a que o cliente mandou refazer. Encerrada (`done`, `failed` com preço) serve; viva com preço
  # parcial também — é a lista que o cliente está lendo.
  def escolher_cotacao
    return nil unless conversation

    cotacoes_com_preco.where.not(status: ::Autonomia::Agents::ToolRun::DEAD_STATUSES).order(id: :desc).first
  end

  # A linha fixada, se ainda é uma cotação com preço e mapa DESTA conversa. Sem filtrar o status: é
  # `dead?` que decide, e a resposta ao cliente é nomeada.
  def cotacao_fixada(id)
    return nil if id.blank? || conversation.nil?

    cotacoes_com_preco.find_by(id: id)
  end

  # A origem ainda serve para uma proposta sair dela? Viva ou encerrada, NUNCA morta, e ainda a
  # ÚLTIMA cotação da conversa. É a MESMA pergunta em quatro lugares: a entrada do `start`, cada
  # passada do `poll`, o encerramento por prazo (`closing_deliveries`) e a publicação efetiva
  # (`publicavel?`).
  def origem_ainda_vale?
    origem = cotacao
    origem.present? && !origem.dead? && ultima_cotacao?(origem)
  end

  # É ELA A COTAÇÃO MAIS RECENTE DESTA CONVERSA? Por id (`cotacoes` já é conta + conversa + slug da
  # cotação), seja qual for o estado da mais nova: viva, com preço, encerrada ou falhada. Uma cotação
  # aberta depois da origem quer dizer que o cliente mandou refazer — e a lista que ele vai ler é a
  # nova. Fora as que NUNCA viraram trabalho (`SEM_TRABALHO`).
  def ultima_cotacao?(origem)
    cotacoes.where.not(status: SEM_TRABALHO).order(id: :desc).limit(1).pick(:id) == origem.id
  end

  # EXECUÇÃO SEM ORIGEM FIXADA: a linha foi aberta antes do deploy desta rodada (uma `pending` que
  # esperava o despacho) ou fora do aceite. Não é "esta conversa não tem cotação" — pode ter, e a
  # escolha do turno é que se perdeu; escolher agora, no job, é justamente o que a rodada 2 proibiu.
  # Só no JOB: no turno a origem é escolhida, e a ausência dela é ausência de cotação mesmo.
  def sem_origem?
    delivery.nil? && params[ORIGEM].blank?
  end

  def cotacoes
    ::Autonomia::Agents::ToolRun.where(account_id: account.id, conversation_id: conversation.id,
                                       slug: ::Autonomia::Agents::Tools::Native::InsuranceQuote.slug)
  end

  # Com número no portal, preço entregue E o mapa de nomes (cotação anterior à entrega 8 não tem o
  # mapa, e sem ele não há como casar o nome: a resposta é "não encontrei cotação").
  def cotacoes_com_preco
    entregues = ::Autonomia::Agents::Tools::Native::InsuranceQuote::DELIVERED_KEY
    cotacoes.where("handle->>'quote_id' IS NOT NULL")
            .where("jsonb_typeof(handle->?) = 'array' AND jsonb_array_length(handle->?) > 0", entregues, entregues)
            .where("jsonb_typeof(handle->?) = 'object'", ::Autonomia::Agents::Tools::Native::InsuranceQuote::NOMES_KEY)
  end

  # A origem no handle do `start`, para o `poll` fixá-la de novo.
  def origem_no_handle
    { ORIGEM => cotacao.id }
  end

  # Código -> nome, como o portal escreveu e o cliente leu.
  def mapa
    @mapa ||= cotacao.handle[::Autonomia::Agents::Tools::Native::InsuranceQuote::NOMES_KEY].to_h.transform_keys(&:to_s)
  end

  # Em ordem alfabética: o jsonb devolve as chaves na ordem dele (tamanho, depois bytes), que não é
  # ordem para uma pessoa ler.
  def cotaram
    mapa.values.sort_by { |nome| ::Autonomia::Agents::Tools::Native::InsuranceProposal::Escolha.normalizar(nome) }
  end

  def quote_id
    cotacao.handle['quote_id'].to_s
  end

  # O mesmo nome do comparativo (entrega 11): a placa que o cliente informou ou, sem ela, o ramo.
  def sufixo_do_arquivo
    quote = ::Autonomia::Agents::Tools::Native::InsuranceQuote
    produto = cotacao.handle['produto'].presence || quote::AUTO
    veiculo = cotacao.arguments['vehicle']
    placa = produto == quote::AUTO && veiculo.is_a?(Hash) ? veiculo['plate'] : nil
    quote::Comparativo.sufixo_do_arquivo(placa: placa, produto: produto)
  end
end
