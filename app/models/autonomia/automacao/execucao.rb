# Uma automação rodando para um alvo: conversa, card ou contato (#2414, F2 #2452). Fica na versão em que entrou.
#
# Só pode haver uma aberta por automação, alvo e gatilho: o índice único do banco vale enquanto `finalizada_em` é nula.
# A exceção (G50) é a `paralela`: o gatilho com `se_repetir: comeca_outra` abre outra execução no mesmo alvo enquanto a
# primeira ainda espera, e o índice não conta as paralelas. O mesmo fato continua abrindo uma só (índice do evento).
# Por isso `finalizada_em` sai daqui, a cada gravação, a partir do estado: nula num estado terminal travaria aquele
# alvo para sempre. Quem grava sem callback (`update_columns`, `update_all`) tem de preencher as duas juntas; o CHECK
# do banco recusa o par desencontrado. A lista de TERMINAIS é a mesma do CHECK da migration.
class Autonomia::Automacao::Execucao < ApplicationRecord
  self.table_name = 'autonomia_automacao_execucoes'

  ABERTAS = %w[andando esperando].freeze
  TERMINAIS = %w[concluida falhou interrompida parada].freeze
  ESTADOS = (ABERTAS + TERMINAIS).freeze
  # Quanto tempo a execução finalizada fica, depois que os registros dela já saíram (30 dias): 90 dias cabe um "não
  # repetir por N dias" e a pergunta "esse cliente já passou por aqui?" sem guardar o histórico passo a passo
  # (#2459, decisão da Automação em 01/11).
  RETENCAO = 90.days
  # O que a execução terminada perde junto (#2679): os textos da IA são cópia de conversa e só valem enquanto ela anda.
  # Quem fecha sem callback grava isto junto da finalizada_em.
  AO_TERMINAR = { textos: {}.freeze }.freeze

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao', inverse_of: :execucoes
  belongs_to :versao, class_name: 'Autonomia::Automacao::Versao'
  belongs_to :alvo, polymorphic: true
  has_many :registros, class_name: 'Autonomia::Automacao::Registro', inverse_of: :execucao, dependent: nil

  validates :estado, inclusion: { in: ESTADOS }
  validates :chave_gatilho, presence: true
  validate :da_mesma_automacao

  before_save :marcar_finalizada

  scope :abertas, -> { where(finalizada_em: nil) }

  # Grava só se a execução ainda está na rodada de `marca` (andando, com essa travada_em). Quem desligou no meio, ou
  # outra rodada, vence: devolve false e nada muda. Sem callback, então leva a finalizada_em junto (ver acima).
  def self.gravar_na_rodada(id, marca, **atributos)
    agora = Time.current
    final = TERMINAIS.include?(atributos.fetch(:estado)) ? agora : nil
    atributos = atributos.merge(AO_TERMINAR) if final
    where(id: id, estado: 'andando', travada_em: marca)
      .update_all(atributos.merge(finalizada_em: final, updated_at: agora)) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  # #2679: o texto que o passo de IA `passo_id` produziu, para os passos seguintes lerem (Valores, `ia.<passo>`). Só na
  # execução ainda aberta: quem a fechou enquanto a IA respondia (desligar, varredura) vence, e o texto não volta para
  # uma execução terminada. Junta no banco (`||`), sem regravar o que outro passo guardou. Devolve se gravou.
  def guardar_texto!(passo_id, texto)
    novo = { passo_id.to_s => texto }
    gravou = self.class.where(id: id, finalizada_em: nil)
                 .update_all(['textos = textos || ?::jsonb', novo.to_json]) == 1 # rubocop:disable Rails/SkipsModelValidations
    return false unless gravou

    self[:textos] = textos.merge(novo)
    clear_attribute_changes([:textos])
    true
  end

  # #2933: a automação de quem valem as permissões, o "ligada" e a pausa desta execução: a de cima de todas, quando esta
  # é a execução de um bloco (Bloco.dona); nas outras, a própria. Quem age nos passos é sempre `dona.ligada_por`.
  def dona = (@dona ||= ::Autonomia::Automacao::Bloco.dona(self))

  private

  # Versão e automação de outra conta prenderiam a exclusão daquela conta nesta chave estrangeira; alvo de outra conta
  # faria o motor agir fora da conta.
  def da_mesma_automacao
    errors.add(:versao, :invalid) if versao && versao.automacao_id != automacao_id
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
    errors.add(:alvo, :invalid) if alvo && ::Autonomia::Automacao::Contexto.de(alvo).conta_id != account_id
  end

  def marcar_finalizada
    terminal = TERMINAIS.include?(estado)
    self.finalizada_em = terminal ? (finalizada_em || Time.current) : nil
    assign_attributes(AO_TERMINAR) if terminal
  end
end
