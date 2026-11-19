# "Tirar etiquetas" da Lista nova de Relacionamentos (#3062): tira as etiquetas escolhidas de cada pessoa marcada e
# deixa as outras. Quem tira é o serviço do lote de hoje (Contacts::BulkRemoveLabelsService), pessoa por pessoa, como em
# AplicarEtiqueta. Quem não tinha nenhuma das escolhidas não muda (nem o updated_at) e não entra na conta de feitas.
# Tirar aceita etiqueta que a conta já apagou: ela continua na pessoa até alguém tirar.
class Relacionamentos::TirarEtiqueta < Relacionamentos::AplicarEtiqueta
  private

  def contagem
    :tiradas
  end

  def preparar
    recusar('etiqueta desconhecida') if @etiquetas.empty?
  end

  def fazer(pessoa_id)
    return SEM_MUDANCA unless @account.contacts.find(pessoa_id).label_list.intersect?(@etiquetas)

    feito = Contacts::BulkRemoveLabelsService.new(account: @account, contact_ids: [pessoa_id], labels: @etiquetas).perform
    NAO_EXISTE_MAIS unless feito[:updated_contact_ids].include?(pessoa_id)
  end
end
