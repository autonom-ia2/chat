# Perfil de um modelo da Meta no Chat2You (#1330): nome amigável, campos do catálogo por variável, arquivo de exemplo do
# topo e o selo "usado pelo sistema". O modelo em si (texto, status, motivo de recusa) vem da lista sincronizada da caixa;
# o perfil só complementa e sobrevive ao sync e à troca de conta. Modelo sem perfil continua funcionando pelo nome técnico.
class WhatsappTemplateProfile < ApplicationRecord
  MAX_FRIENDLY_NAME = 120

  belongs_to :account
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User', optional: true
  has_one_attached :header_file
  # Arquivo de cada cartão do carrossel (#1334), com `metadata['card_index']`: a campanha usa a mesma mídia aprovada.
  has_many_attached :card_files

  validates :name, :language, :waba_id, presence: true
  validates :name, uniqueness: { scope: [:inbox_id, :language] }
  validates :friendly_name, length: { maximum: MAX_FRIENDLY_NAME }
  validate :fields_must_be_a_map
  validate :inbox_must_belong_to_account

  # Os perfis que valem para a caixa: da mesma conta e da mesma WABA (caixas irmãs na mesma WABA enxergam o mesmo modelo).
  scope :for_inbox, lambda { |inbox|
    where(account_id: inbox.account_id, waba_id: inbox.channel.try(:waba_id).to_s)
  }

  def self.key_for(name, language)
    [name.to_s, language.to_s.downcase]
  end

  def key
    self.class.key_for(name, language)
  end

  def card_file(index)
    card_files.detect { |file| file.blob.metadata['card_index'].to_s == index.to_s }
  end

  private

  def fields_must_be_a_map
    return if fields.is_a?(Hash) && fields.values.all?(String)

    errors.add(:fields, :invalid)
  end

  def inbox_must_belong_to_account
    errors.add(:inbox, :invalid) if inbox && inbox.account_id != account_id
  end
end
