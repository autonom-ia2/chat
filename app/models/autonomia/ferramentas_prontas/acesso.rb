# A CHAVE INTERNA DE UMA CONTA NUMA FONTE DO CATÁLOGO (#2858, F0), criada no "Incluir" (`FerramentasProntas::Incluir`).
#
# É a identidade da conta naquela fonte para o contador, o limite diário e o corte. Não é credencial e nunca sai da
# plataforma: nenhuma fonte desta fase pede chave, e a chave da plataforma numa fonte que pedir (F4 em diante) fica em
# variável de ambiente, nunca aqui. Mesmo assim não vai a log: o registro cita a conta e a fonte.
#
# `limite_diario` vazio é o do catálogo (`Fonte#limite_diario`); preenchido, vale só para esta conta nesta fonte.
# `cortada_em` é o corte individual: a fonte para só nesta conta, e as outras seguem.
class Autonomia::FerramentasProntas::Acesso < ApplicationRecord
  self.table_name = 'autonomia_ferramentas_prontas_acessos'

  MAX_MOTIVO = 200

  belongs_to :account

  # Uma por conta e fonte, e a chave única: garantidas pelos índices únicos, que o `create_or_find_by!` do "Incluir"
  # usa para não duplicar quando dois cliques correm.
  validates :fonte, presence: true, inclusion: { in: ->(_) { Autonomia::FerramentasProntas::Catalogo.chaves } }
  validates :chave, presence: true
  validates :limite_diario, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :motivo_do_corte, length: { maximum: MAX_MOTIVO }

  before_validation :gerar_chave, on: :create

  scope :da_conta, ->(account) { where(account_id: account.id) }

  # A chave nunca aparece em `inspect` nem em log de erro do Rails.
  self.filter_attributes += [:chave]

  def cortada?
    cortada_em.present?
  end

  def cortar!(motivo)
    update!(cortada_em: Time.current, motivo_do_corte: motivo.to_s.first(MAX_MOTIVO))
  end

  def religar!
    update!(cortada_em: nil, motivo_do_corte: nil)
  end

  def limite_do_dia
    limite_diario || Autonomia::FerramentasProntas::Catalogo.buscar(fonte)&.limite_diario.to_i
  end

  private

  def gerar_chave
    self.chave ||= "fp_#{SecureRandom.base58(32)}"
  end
end
