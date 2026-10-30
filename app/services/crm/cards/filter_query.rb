class Crm::Cards::FilterQuery
  include Crm::Cards::SharedFilters
  # Lista nova "o que fazer agora" (#2283): sort=acao, waiting, follow_up_status=due, mine e action_group.
  include Crm::Cards::ActionGroups
  # "Mais → Organizar por" (#2379): etapa, quem cuida, retorno, valor, parado e nome.
  include Crm::Cards::OrganizarPor

  FILTER_ATTRIBUTES = %i[pipeline_id inbox_id owner_id priority external_id].freeze
  # List-view-only "Resultado" filter. Uses a DISTINCT param key (`result`) so it
  # never collides with the board filters (the board is strictly open-only and
  # ignores it). `open` is the in-funnel deal status (NOT the conversation
  # status open/pending/resolved); the List status tabs select it explicitly so
  # the default view shows only active deals instead of mixing every status.
  RESULT_STATUSES = %w[open won lost resolved cancelled archived].freeze

  # Whitelisted sort columns for the list view. Maps the public `sort` param to a
  # real `crm_cards` column. Anything outside this map falls back to the default
  # ordering (`updated_at desc`), keeping the SQL byte-identical to the board's
  # historical default when no sort is requested.
  SORTABLE = {
    'score' => :score,
    'value_cents' => :value_cents,
    'next_follow_up_at' => :next_follow_up_at,
    'last_activity_at' => :last_activity_at,
    'entered_stage_at' => :entered_stage_at,
    'title' => :title,
    'updated_at' => :updated_at
  }.freeze

  # #1883: "fechado neste mês" (`closed_in=this_month`), para os links do Números. List-only, como o `result`.
  CLOSED_IN_THIS_MONTH = 'this_month'.freeze
  # #2001 (F6): o "Ver" de Números › "De onde vieram os clientes".
  ORIGENS_PARAMS = %i[entrou_em origem anuncio].freeze

  def initialize(scope:, params:, conversation_visibility:, account: Current.account, account_user: Current.account_user)
    @scope = scope
    @params = params
    @conversation_visibility = conversation_visibility
    @account = account
    @account_user = account_user
  end

  def perform
    cards = apply_filters(base_scope)
    cards = apply_shared_filters(cards)
    cards = apply_standalone_filter(cards)
    cards = apply_search(apply_follow_up_filter(apply_closed_in_filter(apply_result_filter(cards))))
    cards = apply_origens_filter(cards)
    apply_sort(apply_action_groups(cards))
  end

  private

  # Sem sort explícito, a coluna ranqueia por score: quem precisa de atenção primeiro fica no topo.
  # O desempate é o que faz a ordenação servir de verdade — numa coluna com 47 cards e muita nota
  # entre 60 e 80, empate sem critério sai em ordem arbitrária do banco.
  #
  # O desempate é updated_at (o default histórico) de propósito: em conta sem score, todos os cards
  # empatam em 0 e a ordem fica IDÊNTICA à de antes desta mudança. Ranquear é aditivo, não regressão.
  # O desempate final por id é o que torna a paginação estável: sem ele, cards com mesmo score e
  # mesmo updated_at trocam de posição entre consultas e somem ou duplicam entre páginas.
  def apply_sort(cards)
    return cards.order(score: :desc, updated_at: :desc, id: :desc) if @params[:sort].blank?
    return apply_lista_nova_sort(cards) if Crm::Cards::OrganizarPor.lista_nova?(@params)

    column = SORTABLE[@params[:sort].to_s] || :updated_at
    # Valor de venda (#2075): ordenar por valor revelaria o valor; sem `sales_value_view`, vale o padrão.
    column = :updated_at if column == :value_cents && !Crm::ValorDeVenda.ve?(@account_user)
    direction = @params[:direction].to_s == 'asc' ? :asc : :desc
    cards.order(column => direction).order(updated_at: :desc, id: :desc)
  end

  def base_scope
    @scope.includes(:owner, :inbox, :stage, :pipeline,
                    linked_conversations: :conversation_participants,
                    contact: Crm::Cards::CompanyResolver.contact_preload,
                    primary_conversation: [:conversation_participants, { applied_sla: :sla_policy }])
          .preload(primary_conversation: :ai_assignee) # robô responsável (#1377), sem N+1 por card
          # Quem cuida (responsible e current_responsible, #2283): o atendente e o robô ativo da caixa, sem N+1 por card.
          .preload(primary_conversation: [:assignee, { inbox: { agent_bot_inbox: :agent_bot } }],
                   inbox: { agent_bot_inbox: :agent_bot }, account: [])
  end

  def apply_filters(cards)
    FILTER_ATTRIBUTES.reduce(cards) { |filtered_cards, attribute| apply_filter(filtered_cards, attribute) }
  end

  # Every new high-value filter is shared with the board so list/board agree.
  def apply_shared_filters(cards)
    cards = apply_stage_ids_filter(cards)
    cards = apply_team_filter(cards)
    cards = apply_value_range_filter(cards)
    cards = apply_score_range_filter(cards)
    cards = apply_stale_filter(cards)
    cards = apply_responsible_filter(cards)
    cards = apply_label_filter(cards)
    cards = apply_campaign_filter(cards)
    cards = apply_ai_pending_filter(cards)
    apply_company_filter(cards)
  end

  def apply_standalone_filter(cards)
    return cards.standalone if @params[:standalone].to_s == 'true'
    return cards.linked if @params[:standalone].to_s == 'false'

    cards
  end

  def apply_filter(cards, attribute)
    return cards if @params[attribute].blank?

    cards.where(attribute => @params[attribute])
  end

  def apply_result_filter(cards)
    return cards unless RESULT_STATUSES.include?(@params[:result].to_s)

    # Aba de desfecho (#1197): card fechado antes de o funil trocar "conta como venda" continua na aba equivalente.
    result = @params[:result].to_s
    cards.where(status: [result, Crm::Cards::Outcome::NOT_SALE[result], Crm::Cards::Outcome::SALE[result]].compact)
  end

  # O mês é o do fuso da conta (o mesmo dos relatórios do CRM), nunca o do servidor.
  def apply_closed_in_filter(cards)
    return cards unless @params[:closed_in].to_s == CLOSED_IN_THIS_MONTH

    month_start = Crm::Timezone::Resolver.new(account: @account).zone_or_default.now.beginning_of_month
    cards.where(closed_at: month_start..)
  end

  # Números › "De onde vieram os clientes" (#2001, F6): o "Ver" abre a Lista com `entrou_em=AAAA-MM` (quem entrou ou
  # foi ganho no mês, no fuso da conta) e, dentro disso, `origem` (o grupo da origem de primeiro toque) ou `anuncio`
  # (o id do anúncio do primeiro toque). A seleção e a origem são as mesmas da tela (Crm::Numeros::Origens::Cards e
  # Classificador), então a lista tem o tamanho que a tela mostra. List-only, como o `closed_in`. Origem e anúncio só
  # valem junto do mês (sem ele a classificação leria o funil inteiro): link com mês inválido, fora do limite de meses ou
  # com origem/anúncio sem mês mostra a lista vazia, nunca o funil inteiro sem filtro.
  def apply_origens_filter(cards)
    return cards if ORIGENS_PARAMS.all? { |chave| @params[chave].blank? }

    range = entrou_em_range
    return cards.none if range.nil?

    cards = Crm::Numeros::Origens::Cards.do_mes(cards, range, account: @account)
    origem = Crm::Numeros::Origens::Classificador::ORIGENS.find { |grupo| grupo == @params[:origem].to_s }
    anuncio = @params[:anuncio].to_s.presence
    return cards if origem.nil? && anuncio.nil?

    cards.where(id: Crm::Numeros::Origens::Classificador.new(cards, range).ids_de(origem: origem, anuncio: anuncio))
  end

  def entrou_em_range
    return if @params[:entrou_em].blank?

    inicio = Crm::Numeros::Mes.new(account: @account, chave: @params[:entrou_em].to_s).inicio
    inicio..inicio.end_of_month
  rescue Crm::Numeros::Mes::Invalido
    nil
  end

  def apply_search(cards)
    return cards if @params[:search].blank?

    apply_card_search_filter(cards, @params[:search])
  end

  def apply_follow_up_filter(cards)
    case @params[:follow_up_status].presence
    when 'none'
      cards.where(next_follow_up_at: nil)
    when 'pending'
      cards.where.not(next_follow_up_at: nil).where('crm_cards.next_follow_up_at >= ?', Time.current)
    when 'overdue'
      cards.where.not(next_follow_up_at: nil).where('crm_cards.next_follow_up_at < ?', Time.current)
    else
      cards
    end
  end
end
