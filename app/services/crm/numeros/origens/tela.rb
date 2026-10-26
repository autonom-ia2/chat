# CRM › Números › "De onde vieram os clientes" (#2001, F6 do #1871), no formato que a tela lê (o mesmo do adaptador
# falso do protótipo aprovado em 26/10). Quatro perguntas sobre o mês e o funil escolhidos:
# 1. de onde vieram os clientes novos (origem de primeiro toque), com as vendas e o R$ de cada origem;
# 2. qual anúncio trouxe venda;
# 3. quanto custou cada venda (gasto com anúncios, por cliente novo, por venda e o retorno);
# 4. quantos tocaram no anúncio e não mandaram mensagem.
#
# Regras de cada número (as mesmas do "Como contamos" da tela):
# - cliente novo: card que entrou no funil no mês; venda: card ganho no mês (decisão 1, 25/10), mesmo que tenha
#   entrado antes. `lista` é o tamanho da Lista que o "Ver" abre: quem entrou OU foi ganho no mês, naquela origem;
# - os cards saem de um ponto só (Crm::Numeros::Origens::Cards.do_mes), e a origem de cada um do Classificador.
#
# Quem vê o quê (decisões do Rodrigo, 25/10):
# - gasto, custo e toques só em "Todos os funis" (o gasto é da conta toda) e só para quem pode ver os anúncios
#   (`perfil[:gasto]`, Crm::MetaAdsConnectionPolicy#show?). Com um funil escolhido, `gastoEmTodos` convida a trocar.
#   Sem a permissão, `gastoOculto` explica, só quando há gasto;
# - R$ de venda segue `sales_value_view` (#2075, `perfil[:valor]`): sem ela, os valores e o retorno vêm nil e
#   `valorOculto: true`; as contagens ficam.
class Crm::Numeros::Origens::Tela
  def initialize(account:, mes:, funis:, perfil:)
    @account = account
    @mes = mes
    @funis = funis
    @gasto_permitido = perfil[:gasto]
    @valor = perfil[:valor]
  end

  def perform
    base = { mes: @mes.info, moeda: moeda, valorOculto: !@valor, funil: @funis.payload, funilId: @funis.escolhido&.id }
    return base.merge(vazio: true, origens: [], anuncios: [], gasto: nil, gastoOculto: false, gastoEmTodos: false) if origens.empty?

    base.merge(vazio: false, origens: origens, anuncios: anuncios, gasto: gasto_da_tela, gastoOculto: gasto_oculto?,
               gastoEmTodos: gasto_em_todos?)
  end

  # Os cards do mês nos funis escolhidos. Os números são da equipe, como na visão "Equipe" (Crm::Numeros::Equipe): o
  # acesso é por funil (Funis), não por card; os nomes de clientes só saem no arquivo, com o policy_scope da pessoa.
  def cards_do_mes
    Crm::Numeros::Origens::Cards.do_mes(@account.crm_cards.where(pipeline_id: @funis.ids), @mes.range, account: @account)
  end

  # O resto da tela (relatório baixado) lê os mesmos números.
  def linhas
    @linhas ||= Crm::Numeros::Origens::Classificador.new(cards_do_mes, @mes.range).linhas
  end

  def moeda
    @moeda ||= linhas.select(&:venda).map(&:currency).tally.max_by { |_moeda, n| n }&.first || 'BRL'
  end

  # Por clientes novos (e R$), com "outros caminhos" sempre no fim.
  def origens
    @origens ||= begin
      grupos = linhas.group_by(&:tipo).map { |tipo, cards| numeros(cards).merge(tipo: tipo) }.select { |grupo| contou?(grupo) }
      outras, resto = grupos.partition { |grupo| grupo[:tipo] == Crm::Numeros::Origens::Classificador::OUTRAS }
      resto.sort_by { |grupo| [-grupo[:clientes], -grupo[:valor].to_f, grupo[:tipo]] } + outras
    end
  end

  # Por R$ (e vendas, clientes): anúncio sem venda fica no fim.
  def anuncios
    @anuncios ||= linhas.select(&:ad_id).group_by(&:ad_id).map { |ad_id, cards| anuncio(ad_id, cards) }
                        .select { |ad| contou?(ad) }.sort_by { |ad| ordem_do_anuncio(ad) }
  end

  # O gasto do mês na tela: só em "Todos os funis", para quem pode ver e quando existe.
  def gasto_da_tela
    return @gasto_da_tela if defined?(@gasto_da_tela)

    @gasto_da_tela = (resumo_do_gasto if @funis.todos? && @gasto_permitido && gasto_comparavel?)
  end

  private

  # Os clientes que vieram de anúncio da Meta, em todos os funis: a base do "por cliente" e do "por venda".
  def resumo_do_gasto
    de_anuncio = origens.find { |grupo| grupo[:tipo] == Crm::Numeros::Origens::Classificador::ANUNCIO_META } || numeros([])
    {
      total: gasto.total, porCliente: razao(gasto.total, de_anuncio[:clientes]), porVenda: razao(gasto.total, de_anuncio[:vendas]),
      retorno: retorno(de_anuncio), toques: gasto.toques, clientes: de_anuncio[:clientes]
    }
  end

  # Cada 1 gasto trouxe quanto em vendas: tirado do dinheiro, então some sem `sales_value_view` e sem venda.
  def retorno(de_anuncio)
    razao(de_anuncio[:valor], gasto.total) if @valor && de_anuncio[:vendas].positive?
  end

  def contou?(linha)
    linha[:clientes].positive? || linha[:vendas].positive?
  end

  def ordem_do_anuncio(anuncio)
    [-anuncio[:valor].to_f, -anuncio[:vendas], -anuncio[:clientes], anuncio[:id]]
  end

  def gasto
    @gasto ||= Crm::Numeros::Origens::Gasto.new(account: @account, mes: @mes)
  end

  # Gasto em outra moeda que a das vendas não se divide pelas vendas: a tela não mostra (nem custo, nem retorno).
  def gasto_comparavel?
    gasto.existe? && [nil, moeda].include?(gasto.moeda)
  end

  def gasto_oculto?
    @funis.todos? && !@gasto_permitido && gasto_comparavel?
  end

  def gasto_em_todos?
    !@funis.todos? && @funis.ve_todos? && @gasto_permitido && gasto_comparavel?
  end

  def numeros(cards)
    vendas = cards.select(&:venda)
    { clientes: cards.count(&:entrou), vendas: vendas.size, valor: reais(vendas), lista: cards.size }
  end

  def anuncio(ad_id, cards)
    linha = numeros(cards).merge(id: ad_id, titulo: titulo_do_anuncio(ad_id, cards), miniatura: miniatura(ad_id))
    return linha unless gasto_da_tela

    valor = gasto.por_anuncio.fetch(ad_id, 0.0)
    valor.positive? ? linha.merge(gasto: valor, porVenda: razao(valor, linha[:vendas])) : linha
  end

  def reais(vendas)
    (vendas.select { |card| card.currency == moeda }.sum(&:value_cents) / 100.0).round(2) if @valor
  end

  def razao(numerador, denominador)
    return if numerador.nil? || denominador.to_f.zero?

    (numerador.to_f / denominador).round(2)
  end

  def titulo_do_anuncio(ad_id, cards)
    objetos[ad_id]&.name.presence || cards.filter_map(&:headline).first
  end

  def miniatura(ad_id)
    objeto = objetos[ad_id]
    objeto&.image_path || (objeto.thumbnail_url if objeto&.thumbnail_url.to_s.start_with?('https://'))
  end

  def objetos
    @objetos ||= Crm::MetaAdObject.where(account_id: @account.id, meta_object_id: linhas.filter_map(&:ad_id).uniq)
                                  .with_attached_image.index_by(&:meta_object_id)
  end
end
