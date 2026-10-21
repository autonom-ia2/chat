# As pessoas da equipe em CRM › Números, visão "Equipe" (#1992, F5 do #1871): as linhas de "Quem cuidou" e o "Quem
# precisa de ajuda". Uma linha por pessoa e por tipo de funil, em ordem alfabética (nunca um ranking). A IA nunca entra
# aqui: ela tem a linha própria (Crm::Numeros::IaNoTime).
#
# "Precisa de ajuda" é uma linha por pessoa: os retornos atrasados (Vender) e os casos parados há 7 dias (Atender) no
# funil principal, somados, a partir de LIMITE_AJUDA. Cada número abre a fila daquela pessoa. A ordem é pela soma, de
# quem tem mais atraso para quem tem menos, com desempate pelo nome: os MAX_AJUDA que a lista mostra são os que mais
# precisam. Mostra o motivo e a ação, nunca a posição.
class Crm::Numeros::PessoasDaEquipe
  LIMITE_AJUDA = 5
  MAX_AJUDA = 3

  # cards: Crm::Numeros::CardsDaEquipe. valores: { credito: Crm::Numeros::CreditoDaEquipe#perform[:por_pessoa], moeda:,
  # metas: { user_id => cents } (Crm::Numeros::MetasDaEquipe, vazio até a F4) }.
  def initialize(account:, user:, range:, cards:, valores:)
    @account = account
    @user = user
    @range = range
    @cards = cards
    @credito = valores[:credito]
    @moeda = valores[:moeda]
    @metas = valores[:metas]
  end

  def linhas
    @linhas ||= (linhas_de(:venda) + linhas_de(:atende))
  end

  def quantas
    linhas.pluck(:id).uniq.size
  end

  # Quem está no ritmo da própria meta (só com meta, F4): os nomes, e "você" por último.
  def caminho_certo(esperado_pct)
    no_ritmo = linhas.select { |linha| no_ritmo?(linha, esperado_pct) }
    no_ritmo.sort_by { |linha| linha[:voce] ? 1 : 0 }.map { |linha| linha[:voce] ? { voce: true } : { nome: linha[:nome] } }
  end

  # A lista mostra até MAX_AJUDA, de quem tem mais atraso para quem tem menos; a frase do topo conta todos.
  def ajuda
    precisam_de_ajuda.first(MAX_AJUDA)
  end

  def precisam_de_ajuda
    @precisam_de_ajuda ||= ajuda_por_pessoa.select { |item| item[:total] >= LIMITE_AJUDA }
                                           .sort_by { |item| [-item[:total], item[:pessoa][:nome].to_s.downcase] }
  end

  private

  def no_ritmo?(linha, esperado_pct)
    pct = linha.dig(:venda, :pct)
    pct.present? && pct >= esperado_pct
  end

  def linhas_de(tipo)
    return [] unless @cards.tem?(tipo)

    ids = candidatos.select { |id| papeis_de(id).include?(tipo) }
    pessoas.slice(*ids).sort_by { |_id, nome| nome.to_s.downcase }.map do |id, nome|
      { id: id, nome: nome, voce: id == @user.id }.merge(tipo => tipo == :venda ? venda_de(id) : atende_de(id))
    end
  end

  # Quem teve movimento no mês nos funis visíveis: crédito, card aberto ou card recebido.
  def candidatos
    @candidatos ||= (@credito.keys + abertos_de(:venda).to_a + abertos_de(:atende).to_a + recebidos.keys).compact.uniq
  end

  # O papel de cada pessoa (vende / atende) é a mesma régua do "Só eu", só que a Equipe mostra apenas quem é dono de
  # algum card aberto ou teve movimento no mês: quem só enxerga o funil não tem linha (decisão do Rodrigo no #1999).
  # Encaixe com a F4 (#1997): depois do merge dela, a última linha vira `Crm::Numeros::Papel.de(vendeu:, atendeu:)`.
  # O retorno antecipado fica, porque sem movimento o Papel cairia nos funis visíveis.
  def papeis_de(id)
    vendeu = vendeu?(id)
    atendeu = atendeu?(id)
    return [] unless vendeu || atendeu

    [(:venda if vendeu), (:atende if atendeu)].compact
  end

  def vendeu?(id)
    total(id)[:vendas].positive? || abertos_de(:venda).include?(id) || recebidos.key?(id)
  end

  def atendeu?(id)
    total(id)[:resolvidos].positive? || abertos_de(:atende).include?(id)
  end

  def abertos_de(tipo)
    @abertos_de ||= {}
    @abertos_de[tipo] ||= @cards.responsaveis_com_abertos(tipo).to_set
  end

  # Só quem é da conta (o responsável que saiu da conta não vira linha).
  def pessoas
    @pessoas ||= @account.users.to_h { |pessoa| [pessoa.id, pessoa.available_name] }
  end

  def recebidos
    @recebidos ||= @cards.recebidos(@range)
  end

  def total(id)
    @credito[id] || { vendas: 0, valores: {}, resolvidos: 0 }
  end

  def venda_de(id)
    valor = (total(id)[:valores][@moeda].to_i / 100.0).round(2)
    meta = @metas[id] && (@metas[id] / 100.0).round(2)
    { recebeu: recebidos[id].to_i, fechou: total(id)[:vendas], valor: valor, meta: meta,
      pct: meta&.positive? ? ((valor / meta) * 100).round : nil }
  end

  # O prazo por pessoa ainda não é gravado: sem "no prazo" e sem meta de casos (a F4 é só de Vender).
  def atende_de(id)
    { resolveu: total(id)[:resolvidos], noPrazo: nil, meta: nil, pct: nil }
  end

  def ajuda_por_pessoa
    retornos = atrasos(:venda)
    casos = atrasos(:atende)
    (retornos.keys | casos.keys).select { |id| pessoas.key?(id) }.map do |id|
      { pessoa: { id: id, nome: pessoas[id] }, retornos: retornos[id].to_i, casosParados: casos[id].to_i,
        total: retornos[id].to_i + casos[id].to_i }
    end
  end

  # Por responsável: retornos atrasados em Vender, casos parados em Atender.
  def atrasos(tipo)
    return {} unless @cards.tem?(tipo)

    abertos = @cards.abertos(tipo)
    @cards.por_responsavel(tipo == :venda ? @cards.atrasados(abertos) : @cards.parados(abertos))
  end
end
