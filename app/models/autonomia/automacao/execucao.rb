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
  # Quem fecha por fora uma execução que está no meio de uma rodada (parar_por_fora!) deixa o porquê aqui, para a rodada
  # registrá-lo no passo em que ia (Executor#parou_por_fora): o cursor de quem anda não diz o passo. Fica nos `textos`,
  # que a execução terminada já não usa, e é só o motivo, nunca texto de conversa.
  PORQUE = '_parou_por'.freeze

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

  # Fecha por fora da rodada as abertas de `escopo` (o desligar, o "Parar para este card" do #2499), sem callback: a
  # órfã (alvo apagado) não passa no `belongs_to`, e parar não pode falhar por ela. Leva a finalizada_em junto, como o
  # CHECK pede. Trava as linhas antes de ler, pela ordem do id (o desligar e o parar no card ao mesmo tempo não se
  # prendem um ao outro): nenhuma passa de andando a esperando entre a leitura e o fechamento. A que
  # esperava ganha aqui o registro do porquê, no passo da espera (#2750): com ou sem prazo, não some calada do
  # histórico. A que anda leva o porquê (PORQUE), e a rodada o registra no passo em que ia. O motivo nunca é deduzido
  # depois (de a automação estar ligada, por exemplo). Chamar dentro de uma transação. Devolve os ids fechados.
  def self.parar_por_fora!(escopo, motivo)
    linhas = escopo.abertas.order(:id).lock.pluck(:id, :estado, :cursor, :account_id, :automacao_id)
    return [] if linhas.empty?

    agora = Time.current
    esperando, andando = linhas.partition { |linha| linha[1] == 'esperando' }
    fechar_por_fora(esperando, agora, AO_TERMINAR)
    fechar_por_fora(andando, agora, textos: { PORQUE => motivo })
    registrar_esperas(esperando, motivo, agora)
    linhas.map(&:first)
  end

  def self.fechar_por_fora(linhas, agora, atributos)
    return if linhas.empty?

    where(id: linhas.map(&:first))
      .update_all(estado: 'parada', travada_em: nil, finalizada_em: agora, updated_at: agora, **atributos) # rubocop:disable Rails/SkipsModelValidations
  end
  private_class_method :fechar_por_fora

  # Uma linha por espera fechada, numa gravação só.
  def self.registrar_esperas(linhas, motivo, agora)
    return if linhas.empty?

    registros = linhas.map do |id, _estado, cursor, account_id, automacao_id|
      { account_id: account_id, automacao_id: automacao_id, execucao_id: id, passo: cursor || 'inicio', resultado: 'pulado',
        motivo: motivo, dados: {}, created_at: agora }
    end
    ::Autonomia::Automacao::Registro.insert_all!(registros) # rubocop:disable Rails/SkipsModelValidations
  end
  private_class_method :registrar_esperas

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
