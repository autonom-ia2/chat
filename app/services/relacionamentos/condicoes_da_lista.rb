# #3168 — "Por outra informação", na aba Pessoas da Lista nova de Relacionamentos: as linhas que a gaveta "Mais filtros"
# monta, no mesmo formato e com a mesma regra do filtro da lista de contatos de hoje (o payload de `contacts/filter`,
# Contacts::FilterService e lib/filters/filter_keys.yml). Chegam em JSON no parâmetro `condicoes`.
#
# O que o filtro de hoje recusa (informação, "como" ou valor que ele não conhece) aqui vira Relacionamentos::PedidoInvalido,
# que a lista responde com 422: uma linha perdida no caminho mostraria a base inteira. Linha que não é um objeto, lista
# vazia ou com mais de MAXIMO linhas, idem.
class Relacionamentos::CondicoesDaLista
  MAXIMO = 20
  RECUSAS_DO_FILTRO = [
    CustomExceptions::CustomFilter::InvalidAttribute,
    CustomExceptions::CustomFilter::InvalidOperator,
    CustomExceptions::CustomFilter::InvalidQueryOperator,
    CustomExceptions::CustomFilter::InvalidValue
  ].freeze

  def initialize(account, texto)
    @account = account
    @filtrados = montar(linhas_de(texto))
  end

  # Só as pessoas do escopo que passam nas condições. O filtro de hoje lê a mesma base da lista (resolved_contacts).
  def aplicar(escopo)
    escopo.where(id: @filtrados.select(:id))
  end

  private

  def linhas_de(texto)
    linhas = JSON.parse(texto.to_s)
    recusar('condicoes em formato inválido') unless linhas.is_a?(Array) && linhas.all?(Hash)
    recusar("condicoes: de 1 a #{MAXIMO} linhas") unless linhas.size.between?(1, MAXIMO)

    linhas.map(&:with_indifferent_access)
  rescue JSON::ParserError
    recusar('condicoes em formato inválido')
  end

  def montar(linhas)
    Contacts::FilterService.new(@account, nil, { payload: linhas }).perform(count: false)[:contacts]
  rescue *RECUSAS_DO_FILTRO => e
    recusar("condicoes: #{e.message}")
  end

  def recusar(mensagem)
    raise Relacionamentos::PedidoInvalido, mensagem
  end
end
