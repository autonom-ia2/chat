# #3168 — "Por outra informação", na aba Pessoas da Lista nova de Relacionamentos: as linhas que a gaveta "Mais filtros"
# monta, no mesmo formato e com a mesma regra do filtro da lista de contatos de hoje (o payload de `contacts/filter`,
# Contacts::FilterService e lib/filters/filter_keys.yml). Chegam em JSON no parâmetro `condicoes`.
#
# O filtro de hoje confia na tela dele: valor que não é texto, ligação que falta no meio, "como" que o tipo do campo da
# conta não tem viram erro do banco (500) ou filtro pela metade. Aqui cada linha é conferida antes (Conferencia), e o
# que não serve vira Relacionamentos::PedidoInvalido, que a lista responde com 422: uma linha perdida no caminho
# mostraria a base inteira.
#
# A condição vale sobre todas as pessoas da conta; quem decide a base é a consulta (a lista de hoje, ou a conta inteira
# no grupo "No site agora", que mostra o visitante anônimo).
class Relacionamentos::CondicoesDaLista
  RECUSAS_DO_FILTRO = [
    CustomExceptions::CustomFilter::InvalidAttribute,
    CustomExceptions::CustomFilter::InvalidOperator,
    CustomExceptions::CustomFilter::InvalidQueryOperator,
    CustomExceptions::CustomFilter::InvalidValue
  ].freeze

  def initialize(account, texto)
    @account = account
    linhas = Relacionamentos::CondicoesDaLista::Conferencia.new(account, texto).linhas
    @filtrados = montar(linhas)
  end

  # Só as pessoas do escopo que passam nas condições.
  def aplicar(escopo)
    escopo.where(id: @filtrados.select(:id))
  end

  private

  def montar(linhas)
    Relacionamentos::CondicoesDaLista::Filtro.new(@account, nil, { payload: linhas }).perform(count: false)[:contacts]
  rescue *RECUSAS_DO_FILTRO => e
    raise Relacionamentos::PedidoInvalido, "condicoes: #{e.message}"
  end
end
