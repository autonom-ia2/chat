# A visão "Só eu" de CRM › Números (#1897, F3 do #1871), no formato que a tela lê (dashboard/api/crmNumeros.js, o mesmo
# do adaptador falso do protótipo aprovado). Só os números da própria pessoa e uma barra coletiva da equipe, sem nomes;
# nunca o valor dos colegas nem o custo da IA (Decisões 2 e 4).
#
# O papel vem do tipo do funil: quem tem cards em funil de Vender vende, em funil de Atender atende; sem card nenhum,
# os funis que a pessoa enxerga decidem. Sem meta por pessoa até a F4.
class Crm::Numeros::SoEu
  MAX_PROXIMO = 2

  # acesso: Crm::Access::VisiblePipelines da pessoa (o Kanban e o painel enxergam funis diferentes em "Só as suas").
  def initialize(account:, user:, mes:, acesso:)
    @account = account
    @user = user
    @mes = mes
    @visiveis = acesso.apply(account.crm_pipelines)
    @do_painel = acesso.apply_to_reports(account.crm_pipelines)
    @cards = Crm::Numeros::MeusCards.new(account: account, user: user)
  end

  def perform
    return { vazio: true, mes: @mes.info } if @account.crm_pipelines.none?

    {
      vazio: false, papel: papel, mes: @mes.info, moeda: moeda, estimado: credito[:estimado],
      funis: { vendas: funil(@cards.vendendo, :venda), suporte: funil(@cards.atendendo, :atende) },
      topo: vende? ? topo_de_venda : topo_de_atendimento,
      proximo: proximo, vendendo: vende? ? vendendo : nil, atendendo: atende? ? atendendo : nil,
      iaAjudou: ia_ajudou, equipePct: vende? ? Crm::Numeros::EquipePct.new(**equipe_args).perform : nil
    }
  end

  private

  def credito
    @credito ||= Crm::Numeros::Credito.new(account: @account, user: @user, range: @mes.range).perform
  end

  def vende?
    papeis.include?(:venda)
  end

  def atende?
    papeis.include?(:atende)
  end

  def papel
    { %i[venda atende] => 'vende_atende', [:venda] => 'vende', [:atende] => 'atende' }.fetch(papeis)
  end

  def papeis
    @papeis ||= begin
      proprios = []
      proprios << :venda if credito[:vendas].positive? || @cards.vendendo.exists?
      proprios << :atende if credito[:resolvidos].positive? || @cards.atendendo.exists?
      proprios.presence || pelos_funis_visiveis
    end
  end

  def pelos_funis_visiveis
    tipos = @visiveis.distinct.pluck(:counts_as_sale)
    papeis = []
    papeis << :venda if tipos.include?(true)
    papeis << :atende if tipos.include?(false)
    papeis.presence || [:venda]
  end

  def funil(cards, tipo)
    ids = tipo == :venda ? @cards.venda_ids : @cards.atende_ids
    @cards.funil_principal(cards, @visiveis.where(id: ids))
  end

  def moeda
    @moeda ||= credito[:valores].max_by { |_moeda, cents| cents }&.first || meta_do_funil_padrao || 'BRL'
  end

  def meta_do_funil_padrao
    @account.crm_pipelines.where(counts_as_sale: true).order(is_default: :desc, position: :asc, id: :asc)
            .pick(:metadata)&.dig('goals', 'currency').presence
  end

  def reais(cents)
    (cents.to_i / 100.0).round(2)
  end

  def valor_vendido
    reais(credito[:valores][moeda])
  end

  def esperado_pct
    info = @mes.info
    ((info[:dia].to_f / info[:diasNoMes]) * 100).round
  end

  def topo_de_venda
    frase = if atende?
              { tipo: 'eu_vende_atende', resolvidos: credito[:resolvidos], noPrazo: nil }
            else
              { tipo: 'eu_vende', feito: valor_vendido, meta: nil, dias: @mes.info[:diasRestantes] }
            end
    { escopo: 'eu', medida: 'valor', feito: valor_vendido, meta: nil, fechadas: credito[:vendas],
      esperadoPct: esperado_pct, frase: frase, botao: botao_de_venda }
  end

  def topo_de_atendimento
    lembretes = @cards.atrasados(@cards.atendendo).count
    { escopo: 'eu', medida: 'resolvidos', feito: credito[:resolvidos], meta: nil, esperadoPct: esperado_pct,
      frase: { tipo: 'eu_atende', noPrazo: nil, falta: nil, dias: @mes.info[:diasRestantes] },
      botao: lembretes.positive? ? { tipo: 'meus_lembretes', n: lembretes } : { tipo: 'meus_casos' } }
  end

  # Em cascata: retornos atrasados, senão negociações paradas, senão os cards.
  def botao_de_venda
    atrasados = @cards.atrasados(@cards.vendendo).count
    return { tipo: 'meus_atrasados', n: atrasados } if atrasados.positive?

    parados = @cards.parados(@cards.vendendo)
    total = parados.count
    return { tipo: 'meus_cards' } if total.zero?

    { tipo: 'meus_parados', n: total, valor: reais(parados.where(currency: moeda).sum(:value_cents)) }
  end

  def vendendo
    { escopo: 'eu', itens: [
      { tipo: 'fechadas', n: credito[:vendas], valor: valor_vendido },
      { tipo: 'andamento', n: @cards.vendendo.count },
      { tipo: 'atrasados', n: @cards.atrasados(@cards.vendendo).count }
    ] }
  end

  def atendendo
    { escopo: 'eu', itens: [
      { tipo: 'resolvidos', n: credito[:resolvidos] },
      { tipo: 'com_voce', n: @account.conversations.open.where(assignee_id: @user.id).count },
      { tipo: 'deu_certo', n: pesquisas_enviadas }
    ] }
  end

  # "Receberam o 'deu tudo certo?'": a pesquisa de satisfação enviada no mês nas conversas que estão com a pessoa.
  def pesquisas_enviadas
    @account.messages.where(content_type: :input_csat, created_at: @mes.range)
            .joins(:conversation).where(conversations: { assignee_id: @user.id }).count
  end

  def proximo
    return [] if @mes.fechado? || !vende?

    [Crm::Numeros::CampanhaComVoce.new(account: @account, cards: @cards.vendendo, range: @mes.range).perform]
      .compact.first(MAX_PROXIMO)
  end

  # Como no protótipo: quem vende e atende já tem os dois blocos e não ganha este.
  def ia_ajudou
    return if papel == 'vende_atende'

    ajuda = Crm::Numeros::IaAjudou.new(account: @account, user: @user, range: @mes.range, ganhos: credito[:ganhos]).perform
    return if ajuda.nil?

    vende? ? ajuda.merge(tipo: 'venda') : ajuda.except(:viraram).merge(tipo: 'atende')
  end

  def equipe_args
    { account: @account, range: @mes.range, moeda: moeda, pipelines: @do_painel }
  end
end
