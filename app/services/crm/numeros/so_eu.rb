# A visão "Só eu" de CRM › Números (#1897, F3 do #1871), no formato que a tela lê (dashboard/api/crmNumeros.js, o mesmo
# do adaptador falso do protótipo aprovado). Só os números da própria pessoa e uma barra coletiva da equipe, sem nomes;
# nunca o valor dos colegas nem o custo da IA (Decisões 2 e 4).
#
# O papel vem do tipo do funil: quem tem cards em funil de Vender vende, em funil de Atender atende; sem card nenhum,
# os funis que a pessoa enxerga decidem. A meta é a da própria pessoa (F4, #1991, flag `crm_metas`); nunca a dos colegas.
class Crm::Numeros::SoEu
  MAX_PROXIMO = 2

  # acesso: Crm::Access::VisiblePipelines da pessoa (o Kanban e o painel enxergam funis diferentes em "Só as suas").
  # valor_da_equipe: false tira a barra da equipe (% da meta em R$) de quem não tem `sales_value_view` (#2075). Os
  # números da própria pessoa, inclusive o R$ que ela vendeu e a meta dela, ficam.
  def initialize(account:, user:, mes:, acesso:, valor_da_equipe: true)
    @account = account
    @valor_da_equipe = valor_da_equipe
    @user = user
    @mes = mes
    @visiveis = acesso.apply(account.crm_pipelines.active)
    @do_painel = acesso.apply_to_reports(account.crm_pipelines.active)
    @cards = Crm::Numeros::MeusCards.new(account: account, user: user, visiveis: @visiveis)
  end

  def perform
    return { vazio: true, mes: @mes.info } if @account.crm_pipelines.active.none?

    {
      vazio: false, papel: papel, mes: @mes.info, moeda: moeda, estimado: credito[:estimado],
      funis: { vendas: @cards.funil(:venda), suporte: @cards.funil(:atende) },
      topo: vende? ? topo_de_venda : topo_de_atendimento,
      proximo: proximo, vendendo: vende? ? vendendo : nil, atendendo: atende? ? atendendo : nil,
      iaAjudou: ia_ajudou, equipePct: vende? && @valor_da_equipe ? Crm::Numeros::EquipePct.new(**equipe_args).perform : nil
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
    @papeis ||= Crm::Numeros::Papel.de(
      vendeu: credito[:vendas].positive? || @cards.algum?(:venda),
      atendeu: credito[:resolvidos].positive? || @cards.algum?(:atende)
    ) { @visiveis.distinct.pluck(:counts_as_sale) }
  end

  def moeda
    @moeda ||= credito[:valores].max_by { |_moeda, cents| cents }&.first || meta_do_funil_padrao || 'BRL'
  end

  def meta_do_funil_padrao
    @account.crm_pipelines.active.where(counts_as_sale: true).order(is_default: :desc, position: :asc, id: :asc)
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

  def minha_meta
    return @minha_meta if defined?(@minha_meta)

    @minha_meta = Crm::Metas::DaPessoa.new(account: @account, user: @user, mes: @mes, moeda: moeda).reais
  end

  def topo_de_venda
    frase = if atende?
              { tipo: 'eu_vende_atende', resolvidos: credito[:resolvidos], noPrazo: nil }
            else
              { tipo: 'eu_vende', feito: valor_vendido, meta: minha_meta, dias: @mes.info[:diasRestantes] }
            end
    { escopo: 'eu', medida: 'valor', feito: valor_vendido, meta: minha_meta, fechadas: credito[:vendas],
      esperadoPct: esperado_pct, frase: frase, botao: botao_de_venda }
  end

  def topo_de_atendimento
    lembretes = @cards.atrasados(@cards.abertos_no_funil(:atende)).count
    { escopo: 'eu', medida: 'resolvidos', feito: credito[:resolvidos], meta: nil, esperadoPct: esperado_pct,
      frase: { tipo: 'eu_atende', noPrazo: nil, falta: nil, dias: @mes.info[:diasRestantes] },
      botao: lembretes.positive? ? { tipo: 'meus_lembretes', n: lembretes } : { tipo: 'meus_casos' } }
  end

  # Em cascata: retornos atrasados, senão negociações paradas, senão os cards.
  def botao_de_venda
    atrasados = @cards.atrasados(@cards.abertos_no_funil(:venda)).count
    return { tipo: 'meus_atrasados', n: atrasados } if atrasados.positive?

    parados = @cards.parados(@cards.abertos_no_funil(:venda))
    total = parados.count
    return { tipo: 'meus_cards' } if total.zero?

    { tipo: 'meus_parados', n: total, valor: reais(parados.where(currency: moeda).sum(:value_cents)) }
  end

  def vendendo
    { escopo: 'eu', itens: [
      { tipo: 'fechadas', n: credito[:vendas], valor: valor_vendido, lista: na_lista?(:venda, credito[:ganhos]) },
      { tipo: 'andamento', n: @cards.abertos_no_funil(:venda).count },
      { tipo: 'atrasados', n: @cards.atrasados(@cards.abertos_no_funil(:venda)).count }
    ] }
  end

  def atendendo
    { escopo: 'eu', itens: [
      { tipo: 'resolvidos', n: credito[:resolvidos], lista: na_lista?(:atende, credito[:resolvidos_ids]) },
      { tipo: 'com_voce', n: @account.conversations.open.where(assignee_id: @user.id).count },
      { tipo: 'deu_certo', n: pesquisas_enviadas }
    ] }
  end

  # O "Ver" dos fechados abre a Lista do funil principal com responsável = eu (dono atual). Só vira link quando ela
  # mostra exatamente os cards creditados (crédito pelo responsável no fechamento e um funil só); senão, número sem link.
  def na_lista?(tipo, creditados)
    return false if @mes.fechado?

    @cards.fechados_na_lista(tipo, @mes.inicio).sort == creditados.sort
  end

  # "Receberam o 'deu tudo certo?'": a pesquisa de satisfação enviada no mês nas conversas que estão com a pessoa.
  def pesquisas_enviadas
    @account.messages.where(content_type: :input_csat, created_at: @mes.range)
            .joins(:conversation).where(conversations: { assignee_id: @user.id }).count
  end

  def proximo
    return [] if @mes.fechado? || !vende?

    [Crm::Numeros::CampanhaComVoce.new(account: @account, cards: @cards.abertos_no_funil(:venda), range: @mes.range).perform]
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
