# Lote 5 (#2681): o público da campanha que a Automação dispara pode deixar gente de fora. O passo grava as etiquetas
# excluídas no `audience` da campanha como `ExcludeLabel`, ao lado das `Label` do público. Este módulo, posto no
# Whatsapp::OneoffCampaignService pelo config/initializers/campaign_journey_automacao_sem_etiquetas.rb, tira desses
# contatos quem tem alguma etiqueta excluída.
#
# Vale nos dois caminhos do público: o das etiquetas (`label_audience_contacts`) e o da campanha ligada a um público
# importado (`audience_contacts`, do CampaignJourney::AudienceContacts), que não passa pelas etiquetas.
#
# Só a lista de contatos muda. Quem pediu para não receber continua fora pela regra do envio de cada contato, que
# segue igual. Campanha sem `ExcludeLabel` (toda campanha da tela) recebe o mesmo público de antes.
module Autonomia::Automacao::CampanhaSemEtiquetas
  TIPO = 'ExcludeLabel'.freeze

  def self.audiencia(ids) = Array(ids).map { |id| { 'type' => TIPO, 'id' => id } }

  private

  def label_audience_contacts(audience_labels) = sem_etiquetas_excluidas(super)

  def audience_contacts = sem_etiquetas_excluidas(super)

  def sem_etiquetas_excluidas(contatos)
    excluidas = excluded_audience_labels
    return contatos if excluidas.empty?

    contatos.where.not(id: campaign.account.contacts.tagged_with(excluidas, any: true).reselect(:id))
  end

  def excluded_audience_labels
    ids = Array(campaign.audience).select { |item| item['type'] == TIPO }.pluck('id')
    ids.empty? ? [] : campaign.account.labels.where(id: ids).pluck(:title)
  end
end
