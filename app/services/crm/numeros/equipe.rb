# A visão "Equipe" de CRM › Números (#1992, F5 do #1871), no formato que a tela lê (o mesmo do adaptador falso do
# protótipo aprovado): topo, próximo passo, Vendendo, Atendendo, "Quem precisa de ajuda" e "Quem cuidou", com a IA numa
# linha própria. Só os funis que quem abre enxerga no painel: o gestor de vendas vê Vender, o de atendimento vê Atender.
#
# O R$ dos colegas é número comercial e aparece para quem vê a equipe; o custo da IA, só para o administrador ou o
# Financeiro (`financial_view`, #1982).
# `leitura`: quem vê a equipe mas não trabalha no CRM (função só com `crm_view_reports`) vê os números sem os botões.
# `valor`: sem `sales_value_view` (#2075), todo R$ (vendido, meta, parado, por pessoa, da IA) e o "no ritmo da meta" vêm
# vazios, com `valorOculto: true`; as contagens ficam.
class Crm::Numeros::Equipe
  ESPERANDO_MIN = 30
  MAX_PROXIMO = 2
  LINK_IA_ESPERANDO = { da_ia: '1', esperando_min: ESPERANDO_MIN.to_s, no_funil: '1' }.freeze

  # perfil: { dono:, custo:, leitura:, valor: } de quem abre. dono = administrador (o papel na tela); custo =
  # financial_view; valor = sales_value_view.
  def initialize(account:, user:, mes:, acesso:, perfil:)
    @account = account
    @user = user
    @mes = mes
    @dono = perfil[:dono]
    @custo = perfil[:custo]
    @leitura = perfil[:leitura]
    @valor = perfil.fetch(:valor, true)
    @cards = Crm::Numeros::CardsDaEquipe.new(account: account, pipelines: acesso.apply_to_reports(account.crm_pipelines.active))
  end

  def perform
    return { vazio: true, mes: @mes.info } unless vende? || atende?

    {
      vazio: false, papel: papel, mes: @mes.info, moeda: moeda, estimado: credito[:estimado], leitura: @leitura,
      valorOculto: !@valor,
      funis: { vendas: @cards.funil(:venda), suporte: @cards.funil(:atende) },
      topo: topo, proximo: proximo, vendendo: vende? ? vendendo : nil, atendendo: atende? ? atendendo : nil,
      ajuda: @mes.fechado? ? [] : pessoas.ajuda, quemCuidou: quem_cuidou
    }
  end

  private

  def vende?
    @cards.tem?(:venda)
  end

  def atende?
    @cards.tem?(:atende)
  end

  def papel
    return 'dono' if @dono
    return 'leitura' if @leitura

    { [true, true] => 'gestor', [true, false] => 'gestor_vendas', [false, true] => 'gestor_atendimento' }.fetch([vende?, atende?])
  end

  def credito
    @credito ||= Crm::Numeros::CreditoDaEquipe.new(account: @account, range: @mes.range,
                                                   pipeline_ids: @cards.ids(:venda) + @cards.ids(:atende)).perform
  end

  def somado(chave)
    credito[:por_pessoa].values.sum { |total| chave == :valor ? total[:valores][moeda].to_i : total[chave] }
  end

  def moeda
    @moeda ||= moeda_dos_ganhos || moeda_da_meta || 'BRL'
  end

  # A moeda com mais valor ganho no mês.
  def moeda_dos_ganhos
    somas = Hash.new(0)
    credito[:por_pessoa].each_value { |total| total[:valores].each { |codigo, cents| somas[codigo] += cents } }
    somas.max_by { |_codigo, cents| cents }&.first
  end

  def moeda_da_meta
    @account.crm_pipelines.active.where(id: @cards.ids(:venda)).order(is_default: :desc, position: :asc, id: :asc)
            .pick(:metadata)&.dig('goals', 'currency').presence
  end

  # R$ na tela: nil para quem não vê valores de venda.
  def reais(cents)
    (cents.to_i / 100.0).round(2) if @valor
  end

  # A soma das metas do mês dos funis de Vender, na moeda da tela (a mesma conta da barra da equipe, F3). Sem meta: nil.
  def meta_de_venda
    soma_das_metas if @valor
  end

  def soma_das_metas
    metas = @account.crm_pipelines.active.where(id: @cards.ids(:venda)).pluck(:metadata).filter_map do |metadata|
      goals = (metadata || {})['goals'] || {}
      goals['monthly_target_cents'].to_i if (goals['currency'].presence || 'BRL') == moeda
    end
    metas.sum.positive? ? reais(metas.sum) : nil
  end

  def esperado_pct
    ((@mes.info[:dia].to_f / @mes.info[:diasNoMes]) * 100).round
  end

  def topo
    base = { esperadoPct: esperado_pct, botao: @leitura ? nil : botao }
    return base.merge(topo_de_atendimento) unless vende?

    escopo = atende? ? 'empresa' : 'equipe'
    base.merge(escopo: escopo, medida: 'valor', feito: reais(somado(:valor)), meta: meta_de_venda, fechadas: somado(:vendas),
               frase: escopo == 'empresa' ? frase_da_empresa : frase_de_vendas)
  end

  def frase_da_empresa
    { tipo: 'empresa', feito: reais(somado(:valor)), meta: meta_de_venda, resolvidos: somado(:resolvidos), metaResolvidos: nil }
  end

  def frase_de_vendas
    { tipo: 'equipe_vendas', feito: reais(somado(:valor)), meta: meta_de_venda, ajuda: @mes.fechado? ? 0 : pessoas.precisam_de_ajuda.size }
  end

  def topo_de_atendimento
    { escopo: 'equipe', medida: 'resolvidos', feito: somado(:resolvidos), meta: nil,
      frase: { tipo: 'equipe_atende', em10: nil, lembretes: lembretes } }
  end

  def lembretes
    @cards.atrasados(@cards.abertos(:atende)).count
  end

  # Em cascata, sempre uma lista do funil principal: o que está parado ou atrasado, senão os cards da equipe.
  def botao
    return lembretes.positive? ? { tipo: 'lembretes_equipe', n: lembretes } : { tipo: 'casos_equipe' } unless vende?

    abertos = @cards.abertos(:venda)
    atrasados = @cards.atrasados(abertos).count
    parados = @cards.parados(abertos)
    return { tipo: 'parados', n: parados.count, valor: reais(parados.where(currency: moeda).sum(:value_cents)) } if parados.exists?
    return { tipo: 'atrasados_equipe', n: atrasados } if atrasados.positive?

    { tipo: 'cards_equipe' }
  end

  def vendendo
    lista = !@mes.fechado? && @cards.lista_bate?(:venda, @mes.inicio, credito[:ganhos])
    abertos = @cards.abertos(:venda)
    { escopo: 'equipe', itens: [
      { tipo: 'fechadas', n: somado(:vendas), valor: reais(somado(:valor)), lista: lista },
      { tipo: 'andamento', n: abertos.count },
      { tipo: 'atrasados', n: @cards.atrasados(abertos).count }
    ] }
  end

  def atendendo
    lista = !@mes.fechado? && @cards.lista_bate?(:atende, @mes.inicio, credito[:resolvidos])
    abertos = @cards.abertos(:atende)
    { escopo: 'equipe', itens: [
      { tipo: 'resolvidos', n: somado(:resolvidos), lista: lista },
      { tipo: 'lembretes', n: lembretes },
      { tipo: 'parados_atende', n: @cards.parados(abertos).count }
    ] }
  end

  def proximo
    return [] if @mes.fechado? || @leitura

    [sem_responsavel, ia_esperando].compact.first(MAX_PROXIMO)
  end

  def sem_responsavel
    n = vende? ? @cards.ganhos_sem_responsavel(@mes.inicio) : 0
    { tipo: 'sem_responsavel', n: n, aviso: true } if n.positive?
  end

  # As conversas que a IA passou e esperam alguém há mais de 30 min, nos funis que quem abre vê no Números: a mesma conta
  # da caixa com ?da_ia=1&esperando_min=30&no_funil=1 (Crm::ConversationFinderComFiltrosDoLink), com a visibilidade de
  # quem abre.
  def ia_esperando
    contagem = ConversationFinder.new(@user, LINK_IA_ESPERANDO).perform_meta_only
    n = contagem.dig(:count, :all_count).to_i
    { tipo: 'ia_esperando', n: n, ia: ia&.dig(:nome), aviso: true } if n.positive?
  end

  def ia
    return @ia if defined?(@ia)

    @ia = Crm::Numeros::IaNoTime.new(account: @account, range: @mes.range, cards: @cards,
                                     ganhos: { ids: credito[:ganhos], moeda: moeda, valor: @valor }, custo: @custo).perform
  end

  def pessoas
    @pessoas ||= Crm::Numeros::PessoasDaEquipe.new(account: @account, user: @user, range: @mes.range, cards: @cards,
                                                   valores: { credito: credito[:por_pessoa], moeda: moeda, metas: metas,
                                                              visivel: @valor })
  end

  def metas
    Crm::Numeros::MetasDaEquipe.new(account: @account, mes: @mes, pipeline_ids: @cards.ids(:venda), moeda: moeda).por_pessoa
  end

  def quem_cuidou
    {
      pessoas: pessoas.quantas, linhas: pessoas.linhas, foraDaEquipe: pessoas.fora_da_equipe,
      caminhoCerto: pessoas.caminho_certo(esperado_pct),
      reconhecimento: nil, ia: ia, plataforma: vende? && atende? && ia ? plataforma : nil
    }
  end

  def plataforma
    { ia: ia[:nome], atendeu: ia[:atendeu], participou: ia.dig(:venda, :participou), valor: ia.dig(:venda, :valor) }
  end
end
