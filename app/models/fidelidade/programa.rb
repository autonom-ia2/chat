# O cartão fidelidade da conta (#3100, F4 do épico #3095): um por conta. A compra (o card ganho) dá carimbos ou pontos
# pelo valor dela, "a cada" tanto, sem guardar troco: a cada R$ 50, uma compra de R$ 120 dá 2 (os R$ 20 não passam
# para a próxima). Juntou a meta, a pessoa pode receber o prêmio.
#
# `ligado_em`: desde quando a compra conta. Compra fechada antes disso não dá carimbo; pausar e ligar de novo recomeça
# daí (as compras da pausa não contam). Mudar as regras não mexe em quem já tem carimbos.
#
# O valor "a cada" fica em centavos na moeda do cartão; a tela fala em reais inteiros (`a_cada`), como o MontarPrograma.
class Fidelidade::Programa < ApplicationRecord
  self.table_name = 'fidelidade_programas'

  CARIMBOS = 'carimbos'.freeze
  PONTOS = 'pontos'.freeze
  TIPOS = [CARIMBOS, PONTOS].freeze
  META_MINIMA = 2
  # O cartão de carimbos cabe na tela do celular: até 20 bolinhas.
  META_MAXIMA = { CARIMBOS => 20, PONTOS => 100_000 }.freeze
  PREMIO_MAXIMO = 80
  # Sem validade (nil) os carimbos valem para sempre.
  VALIDADES = [3, 6, 12].freeze
  MOEDA = 'BRL'.freeze
  CENTAVOS = 100
  # Perto do prêmio: falta até 20% da meta (meta / 5), no mínimo 1. A mesma régua de regras.js#pertoDoPremio.
  PARTES_DO_PERTO = 5

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  has_many :movimentos, class_name: 'Fidelidade::Movimento', inverse_of: :programa, dependent: nil
  has_many :saldos, class_name: 'Fidelidade::Saldo', inverse_of: :programa, dependent: nil

  validates :account_id, uniqueness: true
  validates :tipo, inclusion: { in: TIPOS }
  validates :a_cada_centavos, numericality: { only_integer: true, greater_than: 0 }
  validates :ganha, numericality: { only_integer: true, greater_than: 0 }
  validates :meta, numericality: { only_integer: true, greater_than_or_equal_to: META_MINIMA }
  validates :premio, presence: true, length: { maximum: PREMIO_MAXIMO }
  validates :validade_meses, inclusion: { in: VALIDADES }, allow_nil: true
  validates :moeda, inclusion: { in: [MOEDA] }
  validate :meta_cabe_no_cartao

  def self.da_conta(account) = find_by(account_id: account.id)

  # Quantos a compra dá: o valor inteiro dividido por "a cada", vezes quantos ganha. O resto não passa para a próxima.
  def da_compra(valor_centavos)
    valor = valor_centavos.to_i
    return 0 unless valor.positive?

    (valor / a_cada_centavos) * ganha
  end

  # Quando vencem os carimbos recebidos em `desde`; nil quando valem para sempre.
  def vence_em(desde) = validade_meses && (desde + validade_meses.months)

  # A partir de quantos a pessoa está "perto do prêmio" (sem ter completado).
  def perto_a_partir = meta - [1, meta / PARTES_DO_PERTO].max

  # A compra conta? Só com o cartão ligado, na moeda dele e fechada depois de ligar.
  def conta_a_compra?(fechada_em, moeda_da_compra)
    ligado && ligado_em.present? && fechada_em.present? && fechada_em >= ligado_em && moeda_da_compra == moeda
  end

  # Como a tela lê (MontarPrograma, PainelDoCartao, a ficha): "a cada" em reais e as datas em segundos.
  def para_a_tela
    { tipo: tipo, a_cada: a_cada_centavos / CENTAVOS, moeda: moeda, ganha: ganha, meta: meta, premio: premio,
      validade_meses: validade_meses, ligado: ligado, ligado_em: ligado_em&.to_i }
  end

  private

  def meta_cabe_no_cartao
    teto = META_MAXIMA[tipo]
    errors.add(:meta, :less_than_or_equal_to, count: teto) if teto && meta.is_a?(Integer) && meta > teto
  end
end
