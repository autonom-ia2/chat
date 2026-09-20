# O que a pessoa está pedindo para o Guia FAZER (issue #536).
#
# Só monta a proposta: qual ação e com quais valores. Nada é executado aqui — o
# que sai daqui vira um texto que a pessoa lê e confirma na tela, e é a
# confirmação que dispara a execução.
#
# O modelo pode entender errado o valor de um campo; por isso a descrição mostra
# os valores exatos ANTES de qualquer confirmação. A proteção contra o modelo
# inventar não é confiar nele: é a pessoa ver o que vai acontecer.
class Autonomia::Guide::EscolhaDaAcao
  INSTRUCAO = <<~TEXTO.freeze
    Você recebe o pedido de quem administra uma plataforma de atendimento e a lista
    de ações disponíveis.

    Se o pedido for para FAZER uma dessas ações, devolva a ação e os valores que a
    pessoa informou. Não invente valor que ela não disse: deixe o campo fora.
    Se o pedido for uma pergunta, um "como faço", ou não corresponder a nenhuma ação
    da lista, devolva ação nula.
  TEXTO

  ESQUEMA = {
    type: 'object',
    properties: {
      acao: { type: %w[string null], description: 'Uma das ações da lista, ou nulo.' },
      nome: { type: %w[string null], description: 'Nome do funil, quando for criar funil.' },
      titulo: { type: %w[string null], description: 'Nome da etiqueta, quando for criar etiqueta.' },
      etapas: { type: %w[array null], items: { type: 'string' }, description: 'Etapas do funil, se ditas.' },
      inbox: { type: %w[string null], description: 'Nome da caixa de entrada mencionada.' },
      funil: { type: %w[string null], description: 'Nome do funil mencionado.' }
    },
    required: %w[acao],
    additionalProperties: false
  }.freeze

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  # Devolve { acao:, dados: } ou nil.
  # Quem separa pedido de pergunta é o modelo, pela INSTRUCAO — não uma lista de
  # verbos. A lista já deixou passar em silêncio "Configura o funil"; o que
  # protege aqui é a permissão e o catálogo fechado, não o vocabulário.
  def para(pedido)
    return nil if pedido.to_s.strip.blank?
    return nil unless administrador?

    credencial = ::Crm::Ai::CredentialResolver.new(account: @account).resolve
    return nil if credencial.blank?

    bruto = perguntar_ao_modelo(credencial, pedido)
    montar(bruto)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][acao] account=#{@account&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  def perguntar_ao_modelo(credencial, pedido)
    cliente = ::Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'guide_acao', account: @account)
    resposta = cliente.create(
      model: modelo, instructions: INSTRUCAO, schema: ESQUEMA, reasoning_effort: 'low', timeout: 12,
      input: "Pedido: #{pedido}\n\nAções disponíveis:\n#{::Autonomia::Guide::Acoes::CATALOGO.join("\n")}"
    )
    texto = resposta.is_a?(Hash) ? (resposta[:text] || resposta['text']) : resposta.to_s
    JSON.parse(texto.to_s)
  rescue JSON::ParserError
    nil
  end

  def montar(bruto)
    return nil if bruto.blank?

    acao = bruto['acao'].presence
    return nil unless ::Autonomia::Guide::Acoes::CATALOGO.include?(acao)

    { acao: acao, dados: dados_para(acao, bruto) }
  end

  def dados_para(acao, bruto)
    case acao
    when 'criar_funil'
      { nome: bruto['nome'], etapas: bruto['etapas'] }.compact
    when 'criar_etiqueta'
      { titulo: bruto['titulo'] }.compact
    when 'ligar_caixa_ao_funil'
      vinculo_por_nome(bruto)
    end
  end

  # O modelo devolve nomes; a execução precisa de identificadores desta conta. A
  # busca é escopada à conta, então nome parecido de outra conta não alcança nada.
  def vinculo_por_nome(bruto)
    inbox = @account.inboxes.find_by('LOWER(name) = ?', bruto['inbox'].to_s.downcase)
    pipeline = @account.crm_pipelines.active.find_by('LOWER(name) = ?', bruto['funil'].to_s.downcase)

    { inbox_id: inbox&.id, pipeline_id: pipeline&.id }.compact
  end

  def modelo
    ::Crm::Ai::Config.respond_to?(:default_model) ? ::Crm::Ai::Config.default_model : 'gpt-4.1-mini'
  end
end
