# DE QUAL COTAÇÃO A PROPOSTA SAI — e quando ela NÃO pode sair (rodada de correção da entrega 8).
#
# A ORIGEM É ESCOLHIDA UMA VEZ, NO ACEITE, E FIXADA. Até 12/09/2026 `precheck` e `start` procuravam,
# cada um por si, "a última cotação com preço desta conversa" — inclusive uma já supersedida, e sem
# olhar se havia uma cotação mais nova ainda sem preço. O cenário (Codex, P1): a cotação A entregou
# preços, o cliente corrigiu o veículo e abriu B; "me manda a da Porto" durante B gerava a proposta
# de A — o risco errado, com cara de certo. Agora:
#   - NO TURNO (há `delivery`), a origem é ESCOLHIDA: a última cotação desta conversa com preço
#     entregue e com o mapa de nomes, VIVA ou ENCERRADA — nunca morta (`ToolRun#dead?`). O aceite a
#     grava nos ARGUMENTOS da execução (`Native::Base#argumentos`, chave `ORIGEM`);
#   - NO JOB (sem `delivery`), a origem é a FIXADA, e só ela: `start` a lê dos argumentos, `poll` do
#     handle (o `start` a copia). Se ela morreu no caminho — supersedida por um pedido novo entre o
#     aceite e o `start`, ou entre o `start` e o `poll` —, a resposta é `cotacao_substituida`, sem
#     chamar o portal e sem entregar nada;
#   - nos TRÊS momentos — turno, `start` e `poll` —, uma cotação mais nova VIVA e ainda sem preço é
#     `cotacao_em_andamento`: o cliente acabou de mandar refazer, e a proposta sairia da lista que
#     ele descartou. Até a rodada 3 o `poll` conferia só `dead?`, e o caso mais comum escapava: uma
#     origem `done` NÃO vira `superseded` quando outra abre (`ToolRun.open!` só supersede a viva),
#     então a proposta da lista velha saía enquanto a nova corria — a mesma janela que o `start`
#     recusa, aberta por dezenas de segundos a minutos (verificador cego, I1);
#   - e a conferência é refeita na PUBLICAÇÃO EFETIVA (`InsuranceProposal#publicavel?`, chamado pelo
#     publicador sob o lock): entre o `poll` e a mensagem há uma cadeia humanizada de até 90 s.
#
# Uma cotação `done` NÃO vira `superseded` quando outra abre. Por isso a origem encerrada continua
# servível depois de um pedido novo, e é a conferência de "em andamento" que barra a proposta
# enquanto os preços novos não chegam.
module Autonomia::Agents::Tools::Native::InsuranceProposal::Origem
  extend ActiveSupport::Concern

  # A chave da cotação de origem: nos ARGUMENTOS da execução (gravada pelo aceite) e no HANDLE
  # (copiada pelo `start`, lida pelo `poll`). É o id da linha da cotação em `autonomia_agent_tool_runs`.
  ORIGEM = 'cotacao_run_id'.freeze

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

  # A origem ainda serve para uma proposta sair dela? Viva ou encerrada, NUNCA morta, e sem uma
  # cotação mais nova correndo sem preço. É a mesma pergunta em três lugares: a entrada do `start`,
  # a de cada passada do `poll` e a da publicação efetiva (`publicavel?`).
  def origem_ainda_vale?
    origem = cotacao
    origem.present? && !origem.dead? && !cotacao_em_andamento?
  end

  # Há uma cotação mais nova CORRENDO e ainda sem preço nesta conversa? Só a última conta: `open!`
  # supersede a viva anterior, então a viva é sempre a mais recente.
  #
  # `running?`, não `active?` (verificador cego, I2): uma `pending` é uma aceitação que o turno ainda
  # não promoveu, e a órfã — o worker morreu entre o aceite e o despacho, e um deploy basta — fica
  # parada até o prazo da linha, até uma hora. Contá-la travaria a proposta por uma cotação que
  # ninguém vai executar. É a mesma convenção de `ToolRun.opened_for_turn?`, pelo mesmo motivo.
  def cotacao_em_andamento?
    return false unless conversation

    ultima = cotacoes.order(id: :desc).first
    ultima.present? && ultima.running? && !cotacoes_com_preco.exists?(id: ultima.id)
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
