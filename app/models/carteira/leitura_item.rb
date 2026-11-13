# Um arquivo de um lote de leitura (E6, #2899): o PDF que a corretora enviou e o que foi lido dele. `campos` é o que o
# leitor achou, em forma canônica (centavos, data ISO), e `duvidas`, os nomes dos campos sem certeza, que o Conferir
# pede para a pessoa preencher. `contact` e `apolice` só são preenchidos ao trazer.
#
# Estados: lendo; lido; recusado (o arquivo não é uma apólice); falhou (não deu para ler).
#
# `campos` e o PDF são dado de cliente. Por isso o item não fica para sempre: `vencidos` são os que já passaram do
# prazo de guarda da leitura (Carteira::Leitura::DIAS_DE_GUARDA_DOS_ITENS), e quem os apaga é o app, com `destroy`,
# para o arquivo sair junto (a cascata do banco apagaria a linha e deixaria o PDF). Nada de `campos` vai para log,
# argumento de job ou cache.
#
# Sem account_id: o item é da leitura. Na exclusão da conta ele sai antes dela (Autonomia::ExclusaoDaConta).
class Carteira::LeituraItem < ApplicationRecord
  self.table_name = 'carteira_leitura_itens'

  ESTADOS = %w[lendo lido recusado falhou].freeze

  belongs_to :leitura, class_name: 'Carteira::Leitura', inverse_of: :itens
  belongs_to :contact, optional: true
  belongs_to :apolice, class_name: 'Carteira::Apolice', optional: true
  has_one_attached :pdf

  validates :estado, inclusion: { in: ESTADOS }
  validates :posicao, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :campos_e_duvidas_na_forma
  validate :pessoa_e_apolice_da_conta, if: -> { will_save_change_to_contact_id? || will_save_change_to_apolice_id? }

  scope :vencidos, ->(agora = Time.current) { where(leitura_id: Carteira::Leitura.com_a_guarda_vencida(agora).select(:id)) }

  private

  def campos_e_duvidas_na_forma
    errors.add(:campos, :invalid) unless campos.is_a?(Hash)
    errors.add(:duvidas, :invalid) unless duvidas.is_a?(Array) && duvidas.all?(String)
  end

  # O banco só confere que a pessoa e a apólice existem, não de quem são.
  def pessoa_e_apolice_da_conta
    conta = leitura&.account_id
    errors.add(:contact, :invalid) if contact && contact.account_id != conta
    errors.add(:apolice, :invalid) if apolice && apolice.account_id != conta
  end
end
