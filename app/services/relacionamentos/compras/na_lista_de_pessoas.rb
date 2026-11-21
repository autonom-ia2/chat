# O que as compras somam à aba Pessoas da Lista de Relacionamentos (#3097), lendo o resumo de compras
# (Relacionamentos::Compra) dentro da consulta que a lista já faz:
#   - os grupos de compra (Campeões, Fiéis, Comprou uma vez, Passou da hora de voltar, os dois "sem comprar" e Nunca
#     comprou), pelo grupo guardado na linha: o mesmo que a ficha mostra e que o gatilho usa;
#   - os filtros "compras" (já comprou, nunca comprou, comprou nos últimos 30, 90 ou 180 dias) e "total acima de" (em
#     reais, a moeda que a conta usa; as outras moedas não entram na soma);
#   - as ordens "mais tempo sem comprar", "compra mais recente", "quem mais comprou" e "quem menos comprou". Quem nunca
#     comprou vai para o fim nas quatro;
#   - o quanto cada grupo já comprou, por moeda (`valores`), para os cartões e a frase do topo.
# O total e as ordens por valor mostram dinheiro: quem não vê valor de venda (Crm::ValorDeVenda) não pede (o controller
# confere, `de_valor?`).
class Relacionamentos::Compras::NaListaDePessoas
  Grupo = Relacionamentos::Compras::Grupo
  DA_CONTA = 'relacionamentos_compras.account_id = :conta_das_compras'.freeze
  COMPROU = "EXISTS (SELECT 1 FROM relacionamentos_compras WHERE relacionamentos_compras.contact_id = contacts.id AND #{DA_CONTA}".freeze
  NO_GRUPO = "contacts.id IN (SELECT relacionamentos_compras.contact_id FROM relacionamentos_compras WHERE #{DA_CONTA} " \
             "AND relacionamentos_compras.grupo = '%s')".freeze
  NUNCA_COMPROU = "NOT #{COMPROU})".freeze
  # Os ids dos grupos são texto escrito no código (Grupo::TODOS), sem aspas: entram direto na condição.
  GRUPOS = Grupo::TODOS.index_with { |grupo| grupo == Grupo::NUNCA ? NUNCA_COMPROU : format(NO_GRUPO, grupo) }.freeze
  COMPRAS = { 'ja_comprou' => nil, 'nunca' => nil, 'ultimos_30' => 30.days, 'ultimos_90' => 90.days, 'ultimos_180' => 180.days }.freeze
  # A coluna da pessoa da linha, para ordenar; quem não tem linha (nunca comprou) fica NULL e vai para o fim.
  DA_LINHA = '(SELECT relacionamentos_compras.%s FROM relacionamentos_compras WHERE relacionamentos_compras.contact_id = contacts.id)'.freeze
  ORDENS = {
    'mais_tempo_sem_comprar' => "#{format(DA_LINHA, 'ultima_em')} ASC NULLS LAST, contacts.id",
    'compra_mais_recente' => "#{format(DA_LINHA, 'ultima_em')} DESC NULLS LAST, contacts.id",
    'mais_comprou' => "#{format(DA_LINHA, 'total_brl_cents')} DESC NULLS LAST, contacts.id",
    'menos_comprou' => "#{format(DA_LINHA, 'total_brl_cents')} ASC NULLS LAST, contacts.id"
  }.freeze
  ORDENS_DE_VALOR = %w[mais_comprou menos_comprou].freeze
  CENTAVOS = 100

  # O pedido (`filtros[total_acima]`, a ordem por valor) mostra dinheiro?
  def self.de_valor?(pedido)
    pedido = pedido.to_h.with_indifferent_access
    pedido.dig(:filtros, :total_acima).present? || ORDENS_DE_VALOR.include?(pedido[:ordem])
  end

  def initialize(account, agora)
    @account = account
    @agora = agora
  end

  def grupos = GRUPOS

  def ordens = ORDENS

  def cortes
    { conta_das_compras: @account.id }
  end

  # As condições dos filtros de compra, para o `where` da lista. Filtro vazio quer dizer "qualquer".
  def filtros(compras, total_acima)
    [do_filtro_compras(compras), do_total(total_acima)].compact
  end

  # Recusa (com o motivo) o valor de filtro que a lista não conhece.
  def motivo_invalido(compras, total_acima)
    return "compras desconhecido: #{compras}" unless compras.nil? || COMPRAS.key?(compras)

    "total_acima inválido: #{total_acima}" unless total_acima.nil? || reais(total_acima)
  end

  # { grupo => [{ moeda, total }] } das pessoas de `pessoas` (a consulta da lista, sem o grupo), mais `todos`.
  def valores(pessoas)
    linhas = Relacionamentos::Compra.where(account_id: @account.id, contact_id: pessoas.select(:id))
                                    .joins('CROSS JOIN LATERAL jsonb_array_elements(relacionamentos_compras.por_moeda) AS moeda')
                                    .group(:grupo, Arel.sql("moeda->>'moeda'"))
                                    .pluck(:grupo, Arel.sql("moeda->>'moeda'"), Arel.sql("SUM((moeda->>'total_cents')::bigint)"))
    por_grupo = linhas.group_by(&:first).transform_values { |itens| somados(itens) }
    por_grupo.merge('todos' => somados(linhas.group_by(&:second).map { |moeda, itens| [nil, moeda, itens.sum(&:third)] }))
  end

  private

  def somados(itens)
    itens.map { |_grupo, moeda, centavos| { moeda: moeda, total: centavos.to_i.fdiv(CENTAVOS) } }.sort_by { |item| -item[:total] }
  end

  def do_filtro_compras(compras)
    return if compras.nil?
    return [NUNCA_COMPROU, cortes] if compras == 'nunca'

    desde = COMPRAS.fetch(compras)
    return ["#{COMPROU})", cortes] unless desde

    ["#{COMPROU} AND relacionamentos_compras.ultima_em >= :desde)", cortes.merge(desde: @agora - desde)]
  end

  def do_total(total_acima)
    return if total_acima.nil?

    ["#{COMPROU} AND relacionamentos_compras.total_brl_cents > :centavos)",
     cortes.merge(centavos: reais(total_acima) * CENTAVOS)]
  end

  def reais(valor)
    numero = Integer(valor.to_s, 10, exception: false)
    numero if numero&.between?(0, 1_000_000_000)
  end
end
