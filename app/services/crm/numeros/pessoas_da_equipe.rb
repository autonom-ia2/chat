# As pessoas da equipe em CRM › Números, visão "Equipe" (#1992, F5 do #1871): as linhas de "Quem cuidou" e o "Quem
# precisa de ajuda". Uma linha por pessoa e por tipo de funil, em ordem alfabética (nunca um ranking). A IA nunca entra
# aqui: ela tem a linha própria (Crm::Numeros::IaNoTime).
#
# "Precisa de ajuda" é quem acumulou retornos atrasados (Vender) ou casos parados há 7 dias (Atender) no funil principal,
# a partir de LIMITE_AJUDA, porque é isso que o "Abrir os retornos de Ana" abre. Mostra o motivo e a ação, nunca a posição.
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

  # A lista mostra até MAX_AJUDA; a frase do topo conta todos (precisam_de_ajuda).
  def ajuda
    precisam_de_ajuda.first(MAX_AJUDA)
  end

  def precisam_de_ajuda
    @precisam_de_ajuda ||= (ajuda_de_venda + ajuda_de_atendimento).sort_by { |item| item[:pessoa][:nome].to_s.downcase }
  end

  private

  def no_ritmo?(linha, esperado_pct)
    pct = linha.dig(:venda, :pct)
    pct.present? && pct >= esperado_pct
  end

  def linhas_de(tipo)
    return [] unless @cards.tem?(tipo)

    ids = tipo == :venda ? ids_de_venda : ids_de_atendimento
    pessoas.slice(*ids).sort_by { |_id, nome| nome.to_s.downcase }.map do |id, nome|
      { id: id, nome: nome, voce: id == @user.id }.merge(tipo => tipo == :venda ? venda_de(id) : atende_de(id))
    end
  end

  def ids_de_venda
    com_venda = @credito.filter_map { |id, total| id if total[:vendas].positive? }
    (com_venda + @cards.responsaveis_com_abertos(:venda) + recebidos.keys).compact.uniq
  end

  def ids_de_atendimento
    com_caso = @credito.filter_map { |id, total| id if total[:resolvidos].positive? }
    (com_caso + @cards.responsaveis_com_abertos(:atende)).compact.uniq
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

  def ajuda_de_venda
    return [] unless @cards.tem?(:venda)

    acima(@cards.por_responsavel(@cards.atrasados(@cards.abertos(:venda)))).map do |id, n|
      { tipo: 'retornos', pessoa: { id: id, nome: pessoas[id] }, recebeu: recebidos[id].to_i, fechou: total(id)[:vendas], n: n }
    end
  end

  def ajuda_de_atendimento
    return [] unless @cards.tem?(:atende)

    acima(@cards.por_responsavel(@cards.parados(@cards.abertos(:atende)))).map do |id, n|
      { tipo: 'casos_parados', pessoa: { id: id, nome: pessoas[id] }, resolveu: total(id)[:resolvidos], n: n }
    end
  end

  def acima(contagem)
    contagem.select { |id, n| n >= LIMITE_AJUDA && pessoas.key?(id) }
  end
end
