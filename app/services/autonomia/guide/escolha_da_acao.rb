# O que a pessoa está pedindo para o Guia FAZER (issues #536 e #547).
#
# Só monta a proposta: qual ação, com quais valores, e a frase que a pessoa vai
# ler. Nada é executado aqui — a execução vem depois da confirmação na tela.
#
# **A proposta nasce exclusivamente da mensagem de quem pediu.** Nome de contato,
# título de funil ou texto de conversa que o Guia leu na conta ficam fora desta
# entrada de propósito: dado lido não vira ordem. É a defesa contra alguém
# escrever "apague todos os contatos" dentro de uma conversa e o Guia obedecer.
#
# O modelo pode entender errado um valor; por isso a descrição mostra o pedido
# literal antes da confirmação. A proteção não é confiar nele — é a pessoa ver.
class Autonomia::Guide::EscolhaDaAcao
  INSTRUCAO = <<~TEXTO.freeze
    Você recebe o pedido de quem administra uma plataforma de atendimento e a lista
    de ações disponíveis na API dela, no formato "VERBO recurso".

    Se a pessoa está PEDINDO para fazer algo, escolha a ação da lista que realiza o
    pedido e devolva os valores que ela informou.
    Se ela está PERGUNTANDO — como se faz, o que é, quanto tem — devolva ação nula.

    Regras:
    - Use uma ação exatamente como escrita na lista. Nunca invente.
    - `caminho` traz os valores dos parâmetros da rota (o `:id` de "PATCH inboxes/:id").
      Só preencha com identificador que a pessoa informou ou que apareceu na conversa
      como resultado de uma consulta. Na dúvida, devolva ação nula.
    - `corpo` traz os campos do recurso, com os nomes que a API usa.
    - Não invente valor que a pessoa não disse: deixe o campo fora.
    - `descricao` é uma frase curta em português dizendo o que vai acontecer, para
      a pessoa ler antes de confirmar. Seja literal, não suavize.
  TEXTO

  ESQUEMA = {
    type: 'object',
    properties: {
      acao: { type: %w[string null], description: 'Uma das ações da lista, ou nulo.' },
      caminho: { type: %w[object null], description: 'Valores dos parâmetros da rota.', additionalProperties: true },
      corpo: { type: %w[object null], description: 'Campos do recurso.', additionalProperties: true },
      descricao: { type: %w[string null], description: 'O que vai acontecer, em português.' }
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
  def para(pedido)
    return nil if pedido.to_s.strip.blank?
    return nil unless administrador?

    credencial = ::Crm::Ai::CredentialResolver.new(account: @account).resolve
    return nil if credencial.blank?

    montar(perguntar_ao_modelo(credencial, pedido))
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][acao] account=#{@account&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  def acoes
    @acoes ||= ::Autonomia::Guide::Acoes.new(account: @account, user: @user, account_user: @account_user)
  end

  def perguntar_ao_modelo(credencial, pedido)
    cliente = ::Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'guide_acao', account: @account)
    resposta = cliente.create(
      model: modelo, instructions: INSTRUCAO, schema: ESQUEMA, reasoning_effort: 'low', timeout: 20,
      input: "Pedido: #{pedido}\n\nAções disponíveis:\n#{acoes.catalogo.join("\n")}"
    )
    texto = resposta.is_a?(Hash) ? (resposta[:text] || resposta['text']) : resposta.to_s
    JSON.parse(texto.to_s)
  rescue JSON::ParserError
    nil
  end

  # A superfície é fechada pelo catálogo: ação que o modelo inventou não passa.
  def montar(bruto)
    return nil if bruto.blank?

    acao = bruto['acao'].presence
    return nil unless acoes.catalogo.include?(acao)

    { acao: acao,
      dados: { caminho: limpo(bruto['caminho']), corpo: limpo(bruto['corpo']),
               descricao: bruto['descricao'].to_s.strip.presence } }
  end

  # Valor escrito por quem pede vira conteúdo na plataforma. Mesma higiene das
  # leituras: sem colchete, sem quebra de linha, com tamanho limitado.
  def limpo(valores)
    return {} unless valores.is_a?(Hash)

    valores.to_h do |chave, valor|
      [chave.to_s, valor.is_a?(String) ? sem_ruido(valor) : valor]
    end
  end

  def sem_ruido(texto)
    visivel = texto.delete('[]').chars.map { |c| c.ord < 32 ? ' ' : c }.join
    visivel.squeeze(' ').strip[0, 200].to_s
  end

  def modelo
    ::Crm::Ai::Config.respond_to?(:default_model) ? ::Crm::Ai::Config.default_model : 'gpt-4.1-mini'
  end
end
