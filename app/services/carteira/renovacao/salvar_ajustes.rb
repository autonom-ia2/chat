# Guardar onde ficam as renovações da conta (E5, #2898): o funil e a etapa em que o card nasce, quantos dias antes do
# fim da vigência e se as mensagens saem. Só muda o que veio. O funil tem de ser um dos que quem pede enxerga e estar
# ativo; a etapa tem de ser dele. Funil e etapa andam juntos: os dois nulos tiram a escolha, e nada mais vira card.
# Quem manda o funil fica como quem escolheu (é quem cuida dos cards, Carteira::Renovacao::CriarCard); quem só muda os
# dias ou as mensagens não, e quem tira a escolha tira também quem escolheu.
#
# As escolhas da cotação da renovação (E8, #2901: quem cota, quem envia, quem responde e a caixa) são conferidas em
# Carteira::Cotacao::Escolhas e entram na mesma gravação. Gravada a caixa nova, ou quem cota (que abre ou fecha a
# cotação), o sistema pede à Meta os 2 modelos da cotação nessa caixa (Carteira::Cotacao::Modelos.pedir, #3055), se a
# cotação está aberta e o dono ligou o Aviso de serviço. Erro ao pedir não desfaz o que foi gravado.
#
# Cada coisa que não dá para guardar vira a recusa dela (CustomExceptions::CarteiraRecusa), que nunca repete o que foi
# mandado. Os cards não nascem aqui: a rotina (Carteira::Renovacao::RotinaJob) os cria na próxima passada.
class Carteira::Renovacao::SalvarAjustes
  CAMPOS = (%w[funilId etapaId dias mensagens] + Carteira::Cotacao::Escolhas::CAMPOS).freeze
  ONDE = %w[funilId etapaId].freeze

  # funis: os funis que quem pede enxerga.
  def initialize(account, dados, user:, funis:)
    @account = account
    @dados = dados.to_h.stringify_keys.slice(*CAMPOS)
    @user = user
    @funis = funis
  end

  def call
    novos = onde.merge(dias).merge(mensagens).merge(Carteira::Cotacao::Escolhas.new(@account, @dados).call)
    guardar(novos)
  rescue ActiveRecord::RecordNotUnique
    # Duas pessoas guardando a primeira escolha da conta ao mesmo tempo: a segunda grava por cima da linha que nasceu.
    guardar(novos)
  end

  private

  def guardar(novos)
    config = Carteira::RenovacaoConfig.find_or_initialize_by(account_id: @account.id)
    Carteira::RenovacaoConfig.transaction(requires_new: true) { config.update!(novos) } unless novos.empty?
    Carteira::Cotacao::Modelos.pedir(config) if config.saved_change_to_inbox_id? || config.saved_change_to_quem_cota?
    config
  end

  def onde
    vieram = ONDE & @dados.keys
    return {} if vieram.empty?

    recusar('funil_desconhecido') unless vieram == ONDE
    return { pipeline: nil, stage: nil, user: nil } if @dados.values_at(*ONDE).all?(&:nil?)

    funil = @funis.active.find_by(id: inteiro(@dados['funilId'])) || recusar('funil_desconhecido')
    etapa = funil.stages.find_by(id: inteiro(@dados['etapaId'])) || recusar('etapa_de_outro_funil')
    { pipeline: funil, stage: etapa, user: @user }
  end

  def dias
    return {} unless @dados.key?('dias')

    numero = inteiro(@dados['dias'])
    recusar('dias_invalidos') unless numero && Carteira::RenovacaoConfig::DIAS.cover?(numero)
    { dias_antes: numero }
  end

  def mensagens
    return {} unless @dados.key?('mensagens')

    recusar('mensagens_invalidas') unless Carteira::RenovacaoConfig::MENSAGENS.include?(@dados['mensagens'])
    { mensagens: @dados['mensagens'] }
  end

  # O número inteiro que veio, como número ou como texto só de dígitos. O resto (1.5, "dez", vazio) é nulo.
  def inteiro(valor)
    valor.is_a?(Integer) ? valor : Integer(valor.to_s, 10, exception: false)
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
