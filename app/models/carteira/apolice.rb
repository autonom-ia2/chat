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
#
# Renovação (E5, #2898): `crm_card` é o card de renovação desta apólice (um card por apólice, índice único no banco);
# `renovacao_card_removido_em` marca que alguém apagou esse card de propósito, e ele não volta nesta vigência;
# `apolice_anterior` é a apólice que esta renovou. O desfecho é um só: `renovado_em` ou `nao_renovou_em`, este com o
# motivo em um toque (`motivo_nao_renovou`) e, no motivo "outro", o que a pessoa escreveu (`motivo_escrito`). Apagar o
# card ou a apólice anterior só anula a coluna.
class Carteira::Apolice < ApplicationRecord
  self.table_name = 'carteira_apolices'

  TIPOS = %w[auto residencial vida empresarial outro].freeze
  ORIGENS = %w[planilha manual pdf conector].freeze
  # Por que não renovou. Sem CHECK no banco: a lista pode crescer.
  MOTIVO_ESCRITO = 'outro'.freeze
  MOTIVOS_DE_NAO_RENOVAR = %w[achou_caro outra_corretora vendeu_o_bem nao_respondeu outro].freeze
  MOTIVO_ESCRITO_MAXIMO = 500

  belongs_to :account
  belongs_to :contact
  belongs_to :company, optional: true
  belongs_to :campaign_import, optional: true
  belongs_to :crm_card, class_name: 'Crm::Card', optional: true
  belongs_to :apolice_anterior, class_name: 'Carteira::Apolice', optional: true
  has_many :eventos, class_name: 'Carteira::ApoliceEvento', inverse_of: :apolice, dependent: :delete_all
  has_one_attached :pdf

  validates :tipo, inclusion: { in: TIPOS }
  validates :origem, inclusion: { in: ORIGENS }
  validates :seguradora, :seguradora_chave, :fim_vigencia, presence: true
  validates :fim_vigencia, comparison: { greater_than_or_equal_to: :inicio_vigencia }, if: -> { inicio_vigencia && fim_vigencia }
  validates :valor_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :numero_e_chave_juntos
  validate :pessoa_e_empresa_da_conta, if: -> { will_save_change_to_contact_id? || will_save_change_to_company_id? }
  validates :motivo_nao_renovou, inclusion: { in: MOTIVOS_DE_NAO_RENOVAR }, allow_nil: true
  validates :motivo_escrito, length: { maximum: MOTIVO_ESCRITO_MAXIMO }
  validate :um_desfecho_so
  validate :motivo_com_o_desfecho
  validate :card_e_anterior_da_conta, if: -> { will_save_change_to_crm_card_id? || will_save_change_to_apolice_anterior_id? }

  private

  # O banco só confere que a pessoa e a empresa existem, não de quem são: apólice de uma conta apontando para o contato
  # de outra mostraria o seguro na ficha errada. Só confere quando um dos dois muda.
  def pessoa_e_empresa_da_conta
    errors.add(:contact, :invalid) if contact && contact.account_id != account_id
    errors.add(:company, :invalid) if company && company.account_id != account_id
  end

  def um_desfecho_so
    errors.add(:nao_renovou_em, :invalid) if renovado_em && nao_renovou_em
  end

  # O motivo só existe em quem não renovou, e o texto escrito só (e sempre) no motivo "outro". Quem fechou o card sem
  # dizer o motivo fica sem ele.
  def motivo_com_o_desfecho
    errors.add(:motivo_nao_renovou, :invalid) if motivo_nao_renovou && nao_renovou_em.nil?
    errors.add(:motivo_escrito, :invalid) if motivo_escrito.present? != (motivo_nao_renovou == MOTIVO_ESCRITO)
  end

  # O banco só confere que o card e a apólice anterior existem, não de quem são. E uma apólice não renova a si mesma.
  def card_e_anterior_da_conta
    errors.add(:crm_card, :invalid) if crm_card && crm_card.account_id != account_id
    errors.add(:apolice_anterior, :invalid) if apolice_anterior && (apolice_anterior.account_id != account_id || apolice_anterior_id == id)
  end

  # O número e a chave dele andam juntos, e a chave nunca é texto vazio (CHECKs `_numero` e `_chaves`).
  def numero_e_chave_juntos
    errors.add(:numero_chave, :invalid) if numero.nil? != numero_chave.nil? || numero_chave == ''
  end
end
