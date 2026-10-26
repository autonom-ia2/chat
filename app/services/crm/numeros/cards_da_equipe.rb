# Os cards da equipe em CRM › Números, visão "Equipe" (#1992, F5 do #1871), nos funis que quem abre enxerga no painel
# (Crm::Access::VisiblePipelines#apply_to_reports), separados pelo tipo do funil (Vender ou Atender).
#
# Cada número conta o mesmo que a lista do "Ver" mostra. O Kanban e a Lista abrem um funil por vez, então os abertos,
# atrasados e parados são do funil principal do tipo (o padrão, senão o primeiro da ordem), com as regras da visão
# "Só eu" (Crm::Numeros::MeusCards): atrasado = retorno vencido, parado = 7 dias sem mensagem nem mudança de etapa.
class Crm::Numeros::CardsDaEquipe
  include Crm::Cards::SharedFilters

  def initialize(account:, pipelines:)
    @account = account
    @params = { responsible_kind: 'none' }
    linhas = pipelines.order(is_default: :desc, position: :asc, id: :asc).pluck(:id, :counts_as_sale)
    @ids = { venda: linhas.filter_map { |id, venda| id if venda }, atende: linhas.filter_map { |id, venda| id unless venda } }
  end

  def ids(tipo)
    @ids[tipo]
  end

  def tem?(tipo)
    @ids[tipo].any?
  end

  def funil(tipo)
    @ids[tipo].first
  end

  def abertos(tipo)
    do_funil.where(status: Crm::Card.statuses[:open], pipeline_id: funil(tipo))
  end

  def atrasados(cards)
    cards.where('crm_cards.next_follow_up_at < ?', Time.current)
  end

  def parados(cards)
    sql = Crm::Numeros::MeusCards::PARADO_SQL
    cards.where("#{sql} IS NULL OR #{sql} < ?", Crm::Numeros::MeusCards::DIAS_PARADO.days.ago)
  end

  # { owner_id => n } dos cards com responsável: o "Abrir os retornos de Ana" filtra o Kanban por ela.
  def por_responsavel(cards)
    cards.where.not(owner_id: nil).group(:owner_id).count
  end

  # A Lista do funil principal (result + closed_in=this_month, sem responsável) mostra exatamente os `ids` contados?
  # Conta no banco, sem trazer os ids da Lista. No teto do crédito (Crm::Numeros::Credito::MAX_CARDS) a conta pode ter
  # sido cortada: aí o número não abre a Lista, que mostraria outro conjunto.
  def lista_bate?(tipo, desde, ids)
    return false if funil(tipo).nil? || ids.size >= Crm::Numeros::Credito::MAX_CARDS

    na_lista = do_funil.where(pipeline_id: funil(tipo), status: Crm::Numeros::MeusCards::FECHADOS, closed_at: desde..)
    na_lista.count == ids.size && na_lista.where(id: ids).count == ids.size
  end

  # Ganhos do mês no funil principal que hoje estão sem responsável nenhum, nem pessoa nem robô: a Lista com
  # result=won, closed_in=this_month e responsible_kind=none (o mesmo filtro do Crm::Cards::SharedFilters).
  def ganhos_sem_responsavel(desde)
    return 0 if funil(:venda).nil?

    ganhos = do_funil.where(pipeline_id: funil(:venda), status: Crm::Card.statuses[:won], closed_at: desde..)
    apply_responsible_filter(ganhos).distinct.count(:id)
  end

  # "Recebeu": os cards criados no mês nos funis de Vender, por responsável de hoje.
  def recebidos(range)
    do_funil.where(pipeline_id: ids(:venda), created_at: range).where.not(owner_id: nil).group(:owner_id).count
  end

  # Quem tem card aberto em cada tipo de funil (em qualquer funil do tipo): entra em "Quem cuidou".
  def responsaveis_com_abertos(tipo)
    do_funil.where(status: Crm::Card.statuses[:open], pipeline_id: ids(tipo)).where.not(owner_id: nil)
            .distinct.pluck(:owner_id)
  end

  private

  # Este contato é (#2084): sem os cards de contato fora do funil (parceiro, não é negócio).
  def do_funil
    Crm::Relacao.cards_do_funil(@account)
  end
end
