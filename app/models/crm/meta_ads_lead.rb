# Cada lead de formulário da Meta que entrou na conta (#2195), um por leadgen_id: o webhook repetido e o "trazer os
# antigos" depois do webhook não criam outro card. Dado pessoal fica no contato, não aqui.
class Crm::MetaAdsLead < ApplicationRecord
  self.table_name = 'crm_meta_ads_leads'

  NAME_LIMIT = 255

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :card, class_name: 'Crm::Card', optional: true

  # Único por conta no índice do banco, não em validação: o Importer reserva o lead pelo INSERT e trata o
  # RecordNotUnique, que é o que segura dois webhooks iguais ao mesmo tempo.
  validates :leadgen_id, presence: true
  validates :received_at, presence: true
end
