# == Schema Information
#
# Table name: autonomia_prospecting_leads
#
#  id                      :bigint           not null, primary key
#  address                 :string
#  category                :string
#  city                    :string
#  company_research_status :string           default("not_researched"), not null
#  consent_refused_at      :datetime
#  country                 :string
#  decision_confidence     :decimal(3, 2)
#  decision_instagram      :string
#  decision_linkedin       :string
#  decision_name           :string
#  decision_research_status :string          default("not_researched"), not null
#  decision_role           :string
#  decision_source_url     :string
#  dedupe_key              :string           not null
#  discard_reason          :string
#  enriched_cnpj           :string
#  enriched_data           :jsonb            not null
#  enriched_email          :string
#  enriched_facebook       :string
#  enriched_instagram      :string
#  enriched_linkedin       :string
#  enriched_whatsapp       :string
#  enrichment_completed_at :datetime
#  enrichment_error        :string
#  enrichment_requested_at :datetime
#  enrichment_source       :string
#  enrichment_status       :string           default("pending"), not null
#  enrichment_summary      :text
#  human_insight           :string
#  latitude                :decimal(10, 6)
#  longitude               :decimal(10, 6)
#  metadata                :jsonb            not null
#  name                    :string           not null
#  negative_factors        :jsonb            not null
#  phone                   :string
#  priority_position       :integer
#  priority_score          :decimal(5, 2)
#  provider                :string           default("mock"), not null
#  rating                  :decimal(3, 2)
#  raw_payload             :jsonb            not null
#  research_attempts       :integer          default(0), not null
#  research_completed_at   :datetime
#  research_error          :string
#  research_requested_at   :datetime
#  research_reused         :boolean          default(FALSE), not null
#  research_started_at     :datetime
#  reviews_count           :integer
#  score                   :decimal(5, 2)
#  score_breakdown         :jsonb            not null
#  search_rank             :integer
#  state                   :string
#  status                  :integer          default("new_lead"), not null
#  website                 :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  company_profile_id      :bigint
#  consent_refused_by_id   :bigint
#  contact_id              :bigint
#  crm_card_id             :bigint
#  prospect_search_id      :bigint
#  provider_place_id       :string
#
# Indexes
#
#  idx_autonomia_prospecting_leads_account_enriched_at             (account_id,enrichment_completed_at)
#  idx_autonomia_prospecting_leads_account_enrichment              (account_id,enrichment_status)
#  idx_autonomia_prospecting_leads_account_priority                (account_id,priority_score)
#  idx_autonomia_prospecting_leads_account_score                   (account_id,score)
#  idx_autonomia_prospecting_leads_account_search_rank             (account_id,search_rank)
#  idx_autonomia_prospecting_leads_consent_refused                 (account_id) WHERE (consent_refused_at IS NOT NULL)
#  idx_autonomia_prospecting_leads_provider_place                  (account_id,provider,provider_place_id) UNIQUE WHERE (provider_place_id IS NOT NULL)
#  index_autonomia_prospecting_leads_on_account_id                 (account_id)
#  index_autonomia_prospecting_leads_on_account_id_and_dedupe_key  (account_id,dedupe_key) UNIQUE
#  index_autonomia_prospecting_leads_on_account_id_and_status      (account_id,status)
#  index_autonomia_prospecting_leads_on_contact_id                 (contact_id)
#  index_autonomia_prospecting_leads_on_crm_card_id                (crm_card_id)
#  index_autonomia_prospecting_leads_on_search_id                  (prospect_search_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (consent_refused_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_card_id => crm_cards.id) ON DELETE => nullify
#  fk_rails_...  (prospect_search_id => autonomia_prospecting_searches.id) ON DELETE => nullify
#
class Autonomia::Prospecting::Lead < ApplicationRecord
  self.table_name = 'autonomia_prospecting_leads'

  belongs_to :account
  belongs_to :search, class_name: 'Autonomia::Prospecting::Search', foreign_key: :prospect_search_id, optional: true, inverse_of: :leads
  belongs_to :contact, optional: true
  belongs_to :crm_card, class_name: 'Crm::Card', optional: true
  # Empresa achada pela pesquisa (#679): perfil compartilhado entre contas, por CNPJ.
  belongs_to :company_profile, class_name: 'Autonomia::Prospecting::CompanyProfile', optional: true

  has_many :list_leads, class_name: 'Autonomia::Prospecting::ListLead', foreign_key: :prospect_lead_id, dependent: :destroy,
                        inverse_of: :lead
  has_many :lists, through: :list_leads, source: :list

  enum status: { new_lead: 0, qualified: 1, discarded: 2, no_consent: 3, ready_for_campaign: 4 }
  # queued: pedido aceito e job na fila (#678). O varredor devolve a failed o que fica preso em queued/running.
  enum enrichment_status: {
    pending: 'pending',
    queued: 'queued',
    running: 'running',
    completed: 'completed',
    failed: 'failed',
    skipped: 'skipped'
  }, _prefix: :enrichment

  # A recusa da pessoa (chat#713, 26/09) não depende do status: descartar ou requalificar não a apaga. Só o "Desfazer"
  # do painel (ContactOptOutSync#withdraw!) volta consent_refused_at a nulo. no_consent segue valendo como recusa, e
  # marcar esse status grava a data.
  belongs_to :consent_refused_by, class_name: 'User', optional: true
  scope :consent_refused, -> { where.not(consent_refused_at: nil).or(where(status: :no_consent)) }

  before_validation :ensure_dedupe_key
  before_save :record_consent_refusal, if: -> { will_save_change_to_status? && no_consent? }
  # Os campos pelos quais a recusa alcança um contato (ConsentVeto#contacts_vetoed_by). O metadata entra pela
  # verificação de WhatsApp, cujo número também conta.
  REFUSAL_REACH_ATTRIBUTES = %w[phone enriched_whatsapp enriched_email contact_id metadata].freeze

  # A recusa segue os números do lead: o recusado que ganha telefone, WhatsApp ou e-mail novo (enriquecimento, busca
  # refeita) marca o contato que já existia com ele, na mesma transação. A mudança da própria recusa é do
  # ContactOptOutSync#update_lead!.
  after_save :mark_refusal_on_new_reach, if: :refusal_reach_changed?

  def consent_refused?
    consent_refused_at.present? || no_consent?
  end

  validates :name, presence: true
  validates :provider, presence: true
  validates :dedupe_key, presence: true, uniqueness: { scope: :account_id }
  validates :discard_reason, presence: true, if: :discarded?
  validates :enrichment_status, presence: true
  validates :company_research_status, :decision_research_status, inclusion: { in: Autonomia::Prospecting::Research::States::ALL }
  validate :linked_records_must_belong_to_account

  private

  def record_consent_refusal
    self.consent_refused_at ||= Time.current
  end

  def refusal_reach_changed?
    consent_refused? && saved_changes.keys.intersect?(REFUSAL_REACH_ATTRIBUTES)
  end

  def mark_refusal_on_new_reach
    Autonomia::Prospecting::ContactOptOutSync.new(account: account).mark_contacts!(self)
  end

  def ensure_dedupe_key
    self.dedupe_key ||= [provider, provider_place_id.presence || name.to_s.downcase.strip].join(':')
  end

  def linked_records_must_belong_to_account
    validate_same_account(:search)
    validate_same_account(:contact)
    validate_same_account(:crm_card)
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
