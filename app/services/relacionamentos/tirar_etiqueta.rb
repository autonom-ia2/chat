# "Tirar etiquetas" da Lista nova de Relacionamentos (#3062): tira as etiquetas escolhidas de cada pessoa marcada e
# deixa as outras. Quem tira é o serviço do lote de hoje (Contacts::BulkRemoveLabelsService), pessoa por pessoa, como em
# AplicarEtiqueta. A pessoa que não tinha a etiqueta conta como feita: ela fica sem, que é o que a tela pediu.
class Relacionamentos::TirarEtiqueta < Relacionamentos::AplicarEtiqueta
  private

  def contagem
    :tiradas
  end

  def fazer(pessoa_id)
    feito = Contacts::BulkRemoveLabelsService.new(account: @account, contact_ids: [pessoa_id], labels: @etiquetas).perform
    NAO_EXISTE_MAIS unless feito[:updated_contact_ids].include?(pessoa_id)
  end
end
