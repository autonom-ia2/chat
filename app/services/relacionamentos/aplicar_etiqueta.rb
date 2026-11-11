# "Etiquetar" da Lista nova de Relacionamentos (#2894): põe a etiqueta em cada pessoa marcada, sem tirar as que ela já
# tem. Quem etiqueta é o serviço do lote de hoje (Contacts::BulkAssignLabelsService), chamado pessoa por pessoa para a
# resposta sair com a contagem e a falha de uma não largar as outras. Só etiqueta que a conta tem.
class Relacionamentos::AplicarEtiqueta < Relacionamentos::AcaoEmGrupo
  def initialize(etiqueta:, **)
    super(**)
    @etiqueta = etiqueta.to_s
  end

  private

  def contagem
    :aplicadas
  end

  def preparar
    recusar('etiqueta desconhecida') unless @account.labels.exists?(title: @etiqueta)
  end

  def fazer(pessoa_id)
    feito = Contacts::BulkAssignLabelsService.new(account: @account, contact_ids: [pessoa_id], labels: [@etiqueta]).perform
    NAO_EXISTE_MAIS unless feito[:updated_contact_ids].include?(pessoa_id)
  end
end
