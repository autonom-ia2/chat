# Lote 5 (#2681): o público da campanha que a Automação dispara pode deixar gente de fora. O passo grava as etiquetas
# excluídas no `audience` da campanha como `ExcludeLabel`, ao lado das `Label` do público. Este módulo, posto no
# Whatsapp::OneoffCampaignService pelo config/initializers/automacao_campanha_sem_etiquetas.rb, tira desses contatos
# quem tem alguma etiqueta excluída.
#
# Só a lista de contatos muda. Quem pediu para não receber continua fora pela regra do envio de cada contato, que
# segue igual. Campanha sem `ExcludeLabel` (toda campanha da tela) recebe o mesmo público de antes.
module Autonomia::Automacao::CampanhaSemEtiquetas
  TIPO = 'ExcludeLabel'.freeze

  def self.audiencia(ids) = Array(ids).map { |id| { 'type' => TIPO, 'id' => id } }

  private

  def label_audience_contacts(audience_labels)
    contatos = super
    excluidas = excluded_audience_labels
    return contatos if excluidas.empty?

    contatos.where.not(id: campaign.account.contacts.tagged_with(excluidas, any: true).reselect(:id))
  end

  def excluded_audience_labels
    ids = Array(campaign.audience).select { |item| item['type'] == TIPO }.pluck('id')
    ids.empty? ? [] : campaign.account.labels.where(id: ids).pluck(:title)
  end
end
