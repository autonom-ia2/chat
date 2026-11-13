# Um seguro de uma pessoa da ficha (E4, #2897): a apólice que a corretora acompanha. A pessoa é sempre o contato; a
# empresa só entra quando o segurado é ela. `seguradora_chave` e `numero_chave` são a forma de comparação de
# `seguradora` e `numero`, e chegam prontas: quem as calcula é quem grava (a leitura da planilha, a correção na tela).
#
# "A mesma apólice" é regra do banco, não validação daqui: o índice único [conta, seguradora_chave, numero_chave,
# fim_vigencia] recusa a segunda com ActiveRecord::RecordNotUnique. O fim da vigência entra para a renovação que mantém
# o número caber ao lado da anterior. Tipo, origem, datas e valor têm CHECK no banco; as validações abaixo só dão o erro
# antes dele.
#
# A história (eventos) sai pela chave em cascata. O PDF não: cascata do banco não apaga arquivo, por isso a chave do
# contato não tem cascata e quem apaga a apólice é o app (na exclusão da conta, Autonomia::ExclusaoDaConta).
class Carteira::Apolice < ApplicationRecord
  self.table_name = 'carteira_apolices'

  TIPOS = %w[auto residencial vida empresarial outro].freeze
  ORIGENS = %w[planilha manual pdf conector].freeze

  belongs_to :account
  belongs_to :contact
  belongs_to :company, optional: true
  belongs_to :campaign_import, optional: true
  has_many :eventos, class_name: 'Carteira::ApoliceEvento', inverse_of: :apolice, dependent: :delete_all
  has_one_attached :pdf

  validates :tipo, inclusion: { in: TIPOS }
  validates :origem, inclusion: { in: ORIGENS }
  validates :seguradora, :seguradora_chave, :fim_vigencia, presence: true
  validates :fim_vigencia, comparison: { greater_than_or_equal_to: :inicio_vigencia }, if: -> { inicio_vigencia && fim_vigencia }
  validates :valor_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :numero_e_chave_juntos
  validate :pessoa_e_empresa_da_conta, if: -> { will_save_change_to_contact_id? || will_save_change_to_company_id? }

  private

  # O banco só confere que a pessoa e a empresa existem, não de quem são: apólice de uma conta apontando para o contato
  # de outra mostraria o seguro na ficha errada. Só confere quando um dos dois muda.
  def pessoa_e_empresa_da_conta
    errors.add(:contact, :invalid) if contact && contact.account_id != account_id
    errors.add(:company, :invalid) if company && company.account_id != account_id
  end

  # O número e a chave dele andam juntos, e a chave nunca é texto vazio (CHECKs `_numero` e `_chaves`).
  def numero_e_chave_juntos
    errors.add(:numero_chave, :invalid) if numero.nil? != numero_chave.nil? || numero_chave == ''
  end
end
