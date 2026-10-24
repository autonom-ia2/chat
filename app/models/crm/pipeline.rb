# == Schema Information
#
# Table name: crm_pipelines
#
#  id            :bigint           not null, primary key
#  counts_as_sale :boolean          default(TRUE), not null
#  description   :text
#  is_default    :boolean          default(FALSE), not null
#  metadata      :jsonb            not null
#  name          :string           not null
#  position      :integer          default(0), not null
#  status        :integer          default("active"), not null
#  when_to_use   :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_crm_pipelines_on_account_id                 (account_id)
#  index_crm_pipelines_on_account_id_and_is_default  (account_id,is_default)
#  index_crm_pipelines_on_account_id_and_position    (account_id,position)
#  index_crm_pipelines_on_account_id_and_status      (account_id,status)
#  index_crm_pipelines_on_created_by_id              (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class Crm::Pipeline < ApplicationRecord
  self.table_name = 'crm_pipelines'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :stages, class_name: 'Crm::PipelineStage', dependent: :destroy
  has_many :pipeline_inboxes, class_name: 'Crm::PipelineInbox', dependent: :destroy
  has_many :inboxes, through: :pipeline_inboxes
  has_many :cards, class_name: 'Crm::Card', dependent: :restrict_with_error

  enum status: { active: 0, archived: 1 }

  before_validation :initialize_followup_days, on: :create
  before_save :turn_off_conversion_sync, unless: :counts_as_sale?

  MAX_WHEN_TO_USE = 1_000
  # Modelo escolhido ao criar o funil (#1498), guardado em metadata['template']. De Vender: VENDAS e RENOVACAO; os outros
  # são de Atender. RENOVACAO, SINISTRO e ENDOSSO (#1802) só aparecem na tela para a corretora (camada
  # seguros/corretora); CARTEIRA (#2083), de Atender, só na tela da saúde (seguros/saude_beneficios). A lista vale para
  # qualquer conta na API, como a dos modelos da corretora. Funil antigo não tem: a tela usa o primeiro modelo do tipo.
  TEMPLATES = %w[VENDAS ATENDIMENTO POS_VENDA COBRANCA AGENDAMENTOS RENOVACAO SINISTRO ENDOSSO CARTEIRA].freeze

  validates :name, presence: true
  # Multifunil (#1145): o "Quando usar" que a IA lê para saber se um pedido é deste funil.
  validates :when_to_use, length: { maximum: MAX_WHEN_TO_USE }
  validates :metadata, jsonb_attributes_length: true
  validate :outcome_labels_format, if: :outcome_labels_changed?

  # Nomes dos desfechos (#1144) em metadata['outcome_labels']: objeto só com success e/ou failure, em texto (#1580).
  # Gravado, cada nome tem até OUTCOME_LABEL_MAX_LENGTH (o caminho pipeline.outcome_labels corta antes de gravar).
  OUTCOME_LABEL_KEYS = %w[success failure].freeze
  OUTCOME_LABEL_MAX_LENGTH = 30

  def self.outcome_labels_valid?(labels)
    labels = labels.to_unsafe_h if labels.respond_to?(:to_unsafe_h)
    labels.is_a?(Hash) && (labels.keys.map(&:to_s) - OUTCOME_LABEL_KEYS).empty? && labels.values.all?(String)
  end

  # Por que este funil não pode ser arquivado agora, ou nil: a conta precisa de um funil ativo e, se este é o principal,
  # de outro principal ativo (vários podem estar marcados como principal). Lê o que está gravado, não o que vai ser:
  # o status a gravar é o próprio arquivamento, e desmarcar o principal na mesma mudança não tira a exigência. A API
  # responde 422 com a mensagem crm.pipelines.archive_<motivo>.
  def motivo_para_nao_arquivar
    return if status_in_database == 'archived'

    outros = account.crm_pipelines.active.where.not(id: id)
    return 'last_active' unless outros.exists?

    'only_default' if (is_default_in_database || is_default?) && !outros.exists?(is_default: true)
  end

  # Tipo do funil (#1498) para a IA: "sell" (Vender) ou "serve" (Atender).
  def kind
    counts_as_sale? ? 'sell' : 'serve'
  end

  private

  # Só confere quando o valor muda: funil antigo com dado fora do formato não trava ao mudar outro campo.
  def outcome_labels_changed?
    (metadata || {})['outcome_labels'] != (metadata_was || {})['outcome_labels']
  end

  def outcome_labels_format
    labels = (metadata || {})['outcome_labels']
    return if labels.nil? || (self.class.outcome_labels_valid?(labels) && labels.values.all? { |label| label.length <= OUTCOME_LABEL_MAX_LENGTH })

    errors.add(:base, I18n.t('crm.pipelines.outcome_labels_invalid'))
  end

  # Funil que não conta como venda (#1144) não manda nada para Meta nem Google, nem mudança de etapa: a sincronização
  # é desligada ao salvar, para não virar conversão de anúncio por engano.
  def turn_off_conversion_sync
    config = (metadata || {}).deep_dup
    %w[meta_sync google_sync].each do |key|
      config[key] = config[key].merge('enabled' => false) if config[key].is_a?(Hash)
    end
    self.metadata = config
  end

  def initialize_followup_days
    config = (metadata || {}).deep_dup
    config['ai'] = {
      'enabled' => true, 'auto_move_enabled' => true, 'attribute_extraction_enabled' => true,
      'score_enabled' => true, 'callback_enabled' => true, 'stale_hours' => Crm::Ai::Config::DEFAULT_STALE_HOURS
    }.merge(config['ai'] || {})
    config['ai']['auto_followup'] ||= {}
    config['ai']['auto_followup']['allowed_days'] ||= [1, 2, 3, 4, 5]
    self.metadata = config
  end
end
