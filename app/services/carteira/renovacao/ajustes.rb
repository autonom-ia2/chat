# "Ajustar renovações" (E5, #2898): o que a tela lê para mostrar onde ficam as renovações da conta. As escolhas de agora
# (`ajustes`), os funis que quem pede enxerga e em quantos dias cada seguro que ainda vale termina (a tela conta
# "com N dias, X seguros entram" sem outra ida ao servidor).
#
# A conta que ainda não escolheu vem com o padrão (60 dias) e sem funil: nada vira card até alguém escolher. O funil só
# vem em `ajustes` quando a escolha vale; `escolha` diz por que não vale (Carteira::RenovacaoConfig#escolha): nunca
# escolheram (`nunca_feita`), o funil escolhido foi arquivado (`funil_arquivado`) ou o funil ou a etapa foram apagados
# (`sumiu`). Nos dois últimos a renovação parou sem ninguém pedir, e a tela avisa e pede outro funil.
#
# A cotação e o conector da seguradora são das entregas deles (E7 e E8): aqui vêm desligados, com a chave presente, para
# a tela não mudar de formato quando chegarem.
#
# As mensagens antes de vencer (se saem, e o exemplo das prévias) NÃO vêm: só existem quando a conta tiver a receita da
# Automação que as manda (E5.6). Sem a receita, a tela não mostra o cartão delas. A escolha continua guardada na conta
# (Carteira::Renovacao::SalvarAjustes aceita `mensagens`), para a receita ler quando chegar.
class Carteira::Renovacao::Ajustes
  DAS_PROXIMAS_ENTREGAS = { aggerLigado: false, cotaSozinha: false, cotaSemConversa: false, agente: nil }.freeze
  DIAS_ATE_O_FIM = 'carteira_apolices.fim_vigencia - CAST(:hoje AS date)'.freeze

  # As escolhas no formato que a tela lê e manda de volta (Carteira::Renovacao::SalvarAjustes).
  def self.guardados(config)
    vale = config.escolhida?
    { funilId: (config.pipeline_id if vale), etapaId: (config.stage_id if vale), dias: config.dias_antes }
  end

  # funis: os funis que quem pede enxerga (vazio com o CRM desligado). pode_mudar: se quem pede pode salvar.
  def initialize(account, funis:, pode_mudar:)
    @account = account
    @funis = funis
    @pode_mudar = pode_mudar
    @hoje = Carteira::Selo.hoje(account)
  end

  def call
    { ajustes: self.class.guardados(config), escolha: config.escolha, funis: Relacionamentos::Funis.new(@funis).call,
      vencimentos: vencimentos, semPermissao: !@pode_mudar }.merge(DAS_PROXIMAS_ENTREGAS)
  end

  private

  def config
    @config ||= Carteira::RenovacaoConfig.find_or_initialize_by(account_id: @account.id)
  end

  def valendo
    Carteira::Apolice.where(account_id: @account.id).where(Carteira::Consulta::VALENDO, hoje: @hoje)
  end

  # Do que termina antes para o que termina depois.
  def vencimentos
    dias = ActiveRecord::Base.sanitize_sql_array([DIAS_ATE_O_FIM, { hoje: @hoje }])
    valendo.order(:fim_vigencia, :id).pluck(Arel.sql(dias))
  end
end
