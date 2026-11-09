# Lote 5 (#2681): o público da campanha que a Automação dispara pode deixar gente de fora. O passo grava as etiquetas
# excluídas no `audience` da campanha como `ExcludeLabel`, ao lado das `Label` do público. Este módulo, posto no
# Whatsapp::OneoffCampaignService pelo config/initializers/campaign_journey_automacao_sem_etiquetas.rb, tira desses
# contatos quem tem alguma etiqueta excluída.
#
# Vale nos dois caminhos do público: o das etiquetas (`label_audience_contacts`) e o da campanha ligada a um público
# importado (`audience_contacts`, do CampaignJourney::AudienceContacts), que não passa pelas etiquetas.
#
# "Todos os contatos" (exemplo 7, passo 2: "a mesma campanha para todos os outros contatos"): o passo grava
# `AllContacts` no lugar das `Label`, e o público passa a ser todos os contatos da conta, menos os excluídos.
#
# Falha fechada (🟡 da revisão do #2686): uma etiqueta excluída apagada entre a criação da campanha e o envio não pode
# sumir da exclusão, senão "todos menos X" iria para todos, inclusive X. Nesse caso nada sai: a campanha para com
# `audience_exclusion_label_missing` (CampaignPause, o registro de por que a campanha não saiu), antes de qualquer
# destinatário. O passo confere o mesmo ao criar a campanha (motivo `campanha_exclusao_apagada` no histórico).
#
# Só a lista de contatos muda. Quem pediu para não receber continua fora pela regra do envio de cada contato, que
# segue igual. Campanha sem `ExcludeLabel` nem `AllContacts` (toda campanha da tela) recebe o mesmo público de antes.
module Autonomia::Automacao::CampanhaSemEtiquetas
  TIPO = 'ExcludeLabel'.freeze
  TODOS = 'AllContacts'.freeze
  ETIQUETA_APAGADA = 'audience_exclusion_label_missing'.freeze

  def self.audiencia(ids) = Array(ids).map { |id| { 'type' => TIPO, 'id' => id } }

  def self.todos = [{ 'type' => TODOS }]

  def self.ids_excluidos(campaign) = Array(campaign.audience).select { |item| item['type'] == TIPO }.map { |item| item['id'].to_i }.uniq

  # As etiquetas excluídas da campanha que não existem mais. Com alguma, a campanha não sai (o `perform` daqui) e não
  # pode ser retomada (CampaignPauses::ResumeReadiness): a etiqueta recriada é outra, então a exclusão não volta.
  def self.etiquetas_apagadas(campaign)
    ids = ids_excluidos(campaign)
    ids.empty? ? [] : ids - campaign.account.labels.where(id: ids).pluck(:id)
  end

  def perform
    return super if campaign.completed? || excluidas_apagadas.empty?

    Rails.logger.warn("[automacao][campanha] campaign=#{campaign.id} parada: etiqueta excluída apagada ids=#{excluidas_apagadas.join(',')}")
    CampaignPauses::Pauser.new(campaign, source: 'system', reason_code: ETIQUETA_APAGADA,
                                         details: { missing_label_ids: excluidas_apagadas }).perform
  end

  private

  def label_audience_contacts(audience_labels) = sem_etiquetas_excluidas(para_todos? ? campaign.account.contacts : super)

  def audience_contacts = sem_etiquetas_excluidas(super)

  def sem_etiquetas_excluidas(contatos)
    titulos = titulos_excluidos
    return contatos if titulos.empty?

    contatos.where.not(id: campaign.account.contacts.tagged_with(titulos, any: true).reselect(:id))
  end

  def para_todos? = Array(campaign.audience).any? { |item| item['type'] == TODOS }

  def ids_excluidos = Autonomia::Automacao::CampanhaSemEtiquetas.ids_excluidos(campaign)

  # Lidas uma vez por envio: o `perform` confere que todas existem antes de montar o público.
  def etiquetas_excluidas
    @etiquetas_excluidas ||= ids_excluidos.empty? ? {} : campaign.account.labels.where(id: ids_excluidos).pluck(:id, :title).to_h
  end

  def excluidas_apagadas = ids_excluidos - etiquetas_excluidas.keys

  def titulos_excluidos = etiquetas_excluidas.values
end
