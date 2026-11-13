# "Ajustar renovações" (E5, #2898): o que a tela lê para mostrar onde ficam as renovações da conta. As escolhas de agora
# (`ajustes`), os funis que quem pede enxerga, em quantos dias cada seguro que ainda vale termina (a tela conta
# "com N dias, X seguros entram" sem outra ida ao servidor) e o exemplo das prévias das mensagens.
#
# A conta que ainda não escolheu vem com o padrão (60 dias, mandando as mensagens) e sem funil: nada vira card até
# alguém escolher. A cotação e o conector da seguradora são das entregas deles (E7 e E8): aqui vêm desligados, com a
# chave presente, para a tela não mudar de formato quando chegarem.
class Carteira::Renovacao::Ajustes
  DAS_PROXIMAS_ENTREGAS = { aggerLigado: false, cotaSozinha: false, cotaSemConversa: false, agente: nil }.freeze
  DIAS_ATE_O_FIM = 'carteira_apolices.fim_vigencia - CAST(:hoje AS date)'.freeze

  # As escolhas no formato que a tela lê e manda de volta (Carteira::Renovacao::SalvarAjustes).
  def self.guardados(config)
    { funilId: config.pipeline_id, etapaId: config.stage_id, dias: config.dias_antes, mensagens: config.mensagens }
  end

  # funis: os funis que quem pede enxerga (vazio com o CRM desligado). pode_mudar: se quem pede pode salvar.
  def initialize(account, funis:, pode_mudar:)
    @account = account
    @funis = funis
    @pode_mudar = pode_mudar
    @hoje = Carteira::Selo.hoje(account)
  end

  def call
    { ajustes: self.class.guardados(config), funis: Relacionamentos::Funis.new(@funis).call, vencimentos: vencimentos,
      semPermissao: !@pode_mudar, exemplo: exemplo }.merge(DAS_PROXIMAS_ENTREGAS)
  end

  private

  def config
    Carteira::RenovacaoConfig.find_or_initialize_by(account_id: @account.id)
  end

  def valendo
    Carteira::Apolice.where(account_id: @account.id).where(Carteira::Consulta::VALENDO, hoje: @hoje)
  end

  # Do que termina antes para o que termina depois.
  def vencimentos
    dias = ActiveRecord::Base.sanitize_sql_array([DIAS_ATE_O_FIM, { hoje: @hoje }])
    valendo.order(:fim_vigencia, :id).pluck(Arel.sql(dias))
  end

  # O seguro que termina primeiro, só com o que a prévia da mensagem mostra: o primeiro nome, o tipo e o fim.
  def exemplo
    seguro = valendo.order(:fim_vigencia, :id).preload(:contact).first
    seguro && { nome: seguro.contact.name.to_s.split.first, tipo: seguro.tipo, termina: seguro.fim_vigencia.iso8601 }
  end
end
