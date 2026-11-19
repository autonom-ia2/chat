# "Etiquetar" da Lista nova de Relacionamentos (#2894): põe as etiquetas em cada pessoa marcada, sem tirar as que ela
# já tem. Quem etiqueta é o serviço do lote de hoje (Contacts::BulkAssignLabelsService), chamado pessoa por pessoa para a
# resposta sair com a contagem e a falha de uma não largar as outras. Só etiqueta que a conta tem.
# #3062 — várias etiquetas de uma vez; "Tirar etiquetas" (TirarEtiqueta) usa a mesma conferência.
class Relacionamentos::AplicarEtiqueta < Relacionamentos::AcaoEmGrupo
  def initialize(etiquetas:, **)
    super(**)
    @etiquetas = Array(etiquetas).map(&:to_s).uniq
  end

  private

  def contagem
    :aplicadas
  end

  # Nenhuma etiqueta, ou uma que a conta não tem, recusa o pedido inteiro antes de começar.
  def preparar
    da_conta = @account.labels.where(title: @etiquetas).count
    recusar('etiqueta desconhecida') if @etiquetas.empty? || da_conta != @etiquetas.size
  end

  def fazer(pessoa_id)
    feito = Contacts::BulkAssignLabelsService.new(account: @account, contact_ids: [pessoa_id], labels: @etiquetas).perform
    NAO_EXISTE_MAIS unless feito[:updated_contact_ids].include?(pessoa_id)
  end
end
