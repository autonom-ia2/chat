# #3168 — o filtro da lista de contatos de hoje (Contacts::FilterService) sobre a conta inteira em vez da base da lista
# de contatos: quem decide a base é a consulta (Relacionamentos::CondicoesDaLista#aplicar).
class Relacionamentos::CondicoesDaLista::Filtro < Contacts::FilterService
  def base_relation
    @account.contacts
  end
end
