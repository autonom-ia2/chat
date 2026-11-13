# Um lote de leitura da carteira (E6, #2899): os PDFs que a corretora enviou de uma vez, ou uma busca no conector (E7).
# É o que o Conferir mostra, o que o histórico lista e o que o Desfazer desfaz. Cada arquivo é um item
# (Carteira::LeituraItem); as apólices que o lote criou apontam para ele (`carteira_apolices.leitura_id`), e é por elas
# que o Desfazer acha o que desfazer, mesmo depois de os itens saírem.
#
# `totais` guarda só contagens (quantos lidos, quantos recusados): nome, documento, telefone e texto do PDF nunca entram
# ali. A validação recusa qualquer valor que não seja número inteiro.
#
# O banco só lista as origens. Os estados crescem com quem grava (o anexar, o trazer por PDFs, a busca no conector) e
# são validados aqui.
class Carteira::Leitura < ApplicationRecord
  self.table_name = 'carteira_leituras'

  ORIGENS = %w[pdf conector].freeze
  # lendo: os itens ainda estão sendo lidos. lida: pronta para conferir. trazendo: gravando as apólices. trazida:
  # confirmada (`confirmada_em`). desfeita: o Desfazer rodou (`desfeita_em`).
  ESTADOS = %w[lendo lida trazendo trazida desfeita].freeze
  # Os itens guardam dado de cliente (o que foi lido e o PDF). Saem este tanto de dias depois de a leitura ser
  # confirmada; a que ninguém confirmou conta a partir da última vez em que foi mexida (abandonada).
  DIAS_DE_GUARDA_DOS_ITENS = 30

  belongs_to :account
  belongs_to :user, optional: true
  has_many :itens, class_name: 'Carteira::LeituraItem', inverse_of: :leitura, dependent: :destroy
  has_many :apolices, class_name: 'Carteira::Apolice', inverse_of: :leitura, dependent: :nullify

  validates :origem, inclusion: { in: ORIGENS }
  validates :estado, inclusion: { in: ESTADOS }
  validate :totais_so_com_contagens

  # As leituras cujos itens já passaram do prazo de guarda.
  scope :com_a_guarda_vencida, lambda { |agora = Time.current|
    where('COALESCE(carteira_leituras.confirmada_em, carteira_leituras.updated_at) < ?', agora - DIAS_DE_GUARDA_DOS_ITENS.days)
  }

  private

  def totais_so_com_contagens
    errors.add(:totais, :invalid) unless totais.is_a?(Hash) && totais.values.all?(Integer)
  end
end
