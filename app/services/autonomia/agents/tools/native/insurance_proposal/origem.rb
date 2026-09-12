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
  # QUEM NUNCA VIROU TRABALHO NÃO É RECOTAÇÃO — e "nunca trabalhou" é pergunta por ESTADO, não uma
  # lista de status (rodada 5). Até aqui a lista era a de `ToolRun.opened_for_turn?`
  # (`pending discarded blocked`), copiada de uma pergunta PARECIDA e DIFERENTE: lá significa "ainda
  # não virou trabalho NESTE TURNO"; aqui, "NUNCA trabalhou".
  #
  #   - `discarded` nunca trabalhou e nunca vai: o turno morreu antes do despacho.
  #   - `pending` DEPENDE DA IDADE. A mesma lista tratava como órfã tanto a aceitação que vai promover
  #     em milissegundos quanto a que ficou parada porque o worker morreu — e era por essa fresta que
  #     a proposta antiga publicava enquanto a cotação nova promovia: `ToolRun#promote!` corre sob o
  #     advisory lock do slug e o publicador sob o lock da CONVERSA, mecanismos disjuntos. A idade
  #     desfaz a ambiguidade, e desde a rodada 6 ela vale TAMBÉM NA ESCRITA: `promote!` recusa (e
  #     descarta) a `pending` que passou do teto. Enquanto a recusa existia só aqui, a linha de dez
  #     minutos era ignorada na consulta e promovida assim mesmo — a janela seguia aberta pelo outro
  #     lado. Fora do teto, é a órfã do I2, que o varredor recolhe em uma hora (`PENDING_MAX_AGE`).
  #   - `blocked` DEPENDE DO TRABALHO FEITO. Quem a escreve é `AsyncRunJob#block_run`, quando o
  #     operador puxa o freio (kill-switch da conta, agente desligado, conversa fora da allowlist) —
  #     e isso acontece DEPOIS de a cotação ter rodado, às vezes depois de ela já ter entregado preço.
  #     Tratá-la como "nunca trabalhou" fazia a cotação nova sumir da conta, a antiga voltar a ser "a
  #     última", e a proposta do risco velho publicar depois de uma recotação real — o P1 da rodada 3
  #     reaberto por outra transição. Trabalhou quem tem número no portal, já entregou alguma coisa
  #     OU está com o ENVIO INCERTO (rodada 6, P1-D): a intenção anotada sem número (entrega 5) é,
  #     por definição, a cotação que pode ter chegado ao portal SEM número e SEM entrega — os dois
  #     sinais que o critério pedia. Barrada nesse estado, ela sumia da conta e a proposta do risco
  #     velho voltava a publicar; a pergunta é a mesma que `ToolRun#envio_incerto?` responde, aqui
  #     escrita em SQL como o `finish!` já a escreve.
  DESCARTADA = 'discarded'.freeze
  PENDENTE = 'pending'.freeze
  BLOQUEADA = 'blocked'.freeze
  # O MESMO TETO DA ESCRITA, POR REFERÊNCIA (rodada 6, P1-C): leitura e escrita divergirem sobre
  # "esta `pending` ainda vira trabalho?" é o defeito, e duas constantes com o mesmo nome em dois
  # arquivos é como ele volta. A decisão e o porquê dos 5 minutos moram em `ToolRun::PROMOCAO_ATE`.
  PROMOCAO_ATE = ::Autonomia::Agents::ToolRun::PROMOCAO_ATE

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
  # nova. Fora as que NUNCA viraram trabalho (ver as constantes no alto).
  def ultima_cotacao?(origem)
    ultima_das_cotacoes&.id == origem.id
  end

  # A cotação mais recente que CONTA como recotação nesta conversa, ou nil quando não há nenhuma.
  def ultima_das_cotacoes
    cotacoes_que_contam.order(id: :desc).first
  end

  # As que contam: nem descartada, nem `pending` velha demais para ainda ser promovida, nem `blocked`
  # que nunca chegou a trabalhar — sem número no portal, sem nada entregue ao cliente E sem envio
  # incerto (a intenção anotada que nunca virou número: pode haver cotação no portal).
  def cotacoes_que_contam
    intencoes = ::Autonomia::Agents::ToolRun::INTENCOES
    submetido = ::Autonomia::Agents::ToolRun::SUBMITTED_KEY
    cotacoes.where.not(status: DESCARTADA)
            .where('status <> ? OR created_at > ?', PENDENTE, PROMOCAO_ATE.ago)
            .where("status <> ? OR delivered_count > 0 OR handle->>'quote_id' IS NOT NULL OR " \
                   '(COALESCE((handle->>?)::int, 0) > 0 AND (handle->>?) IS NULL)',
                   BLOQUEADA, intencoes, submetido)
  end

  # A RECOTAÇÃO ENCERROU SEM TRAZER PREÇO NENHUM? (rodada 5, achado do verificador cego.) A REGRA NÃO
  # MUDA — a origem antiga continua não valendo, e incluir a `failed` sem preço em "nunca trabalhou"
  # reabriria o R7 —, mas a FRASE precisa ser outra: prometer "quando os preços novos chegarem, é só
  # me pedir de novo" a quem tem uma recotação MORTA sem preço é prometer o que não vem, e o cliente
  # fica preso para sempre, com os preços antigos na tela e a proposta deles barrada.
  #
  # Só vale para a cotação NOVA (nunca para a própria origem, que pode ter morrido sendo a última) e
  # só depois de ela encerrar: enquanto está viva, os preços ainda podem chegar — e aí a frase certa
  # é a de sempre.
  def recotacao_sem_preco?
    nova = ultima_das_cotacoes
    nova.present? && nova.id != cotacao&.id && encerrada_sem_preco?(nova)
  end

  def encerrada_sem_preco?(nova)
    ::Autonomia::Agents::ToolRun::ACTIVE_STATUSES.exclude?(nova.status) &&
      Array(nova.handle.to_h[::Autonomia::Agents::Tools::Native::InsuranceQuote::DELIVERED_KEY]).empty?
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
