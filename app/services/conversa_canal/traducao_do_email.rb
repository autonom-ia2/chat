# Tradução de e-mail pela IA da conta (#1786), para quem não ligou o Google Tradutor (decisão do Rodrigo, 18/10:
# "IA da conta, Google se houver"). Mesma chave do ditado e do CRM (Crm::Ai::CredentialResolver). Traduz o HTML do
# e-mail mantendo a marcação (tabelas, listas, links, imagens), para a tela mostrar a tradução com a mesma cara.
# Só para a conversa de e-mail nova (chave `conversa_email_nova`); os outros canais seguem só com o Google.
# Roda num job (ConversaCanal::TraduzirEmailJob): o HTML vai e volta inteiro e passa dos 15 s da requisição.
class ConversaCanal::TraducaoDoEmail
  # E-mail muito grande (newsletter com HTML pesado) não vai para a IA: custo e tempo sem retorno.
  LIMITE_DE_CARACTERES = 60_000
  # Os idiomas que o painel oferece (os mesmos da troca de idioma do perfil e da conta).
  IDIOMAS_DO_PAINEL = LANGUAGES_CONFIG.values.pluck(:iso_639_1_code).freeze
  ESQUEMA = {
    name: 'traducao_do_email',
    schema: {
      type: 'object',
      properties: { traducao: { type: 'string' } },
      required: %w[traducao],
      additionalProperties: false
    }
  }.freeze

  def self.aplica?(message)
    message&.inbox&.email? &&
      message.account.feature_enabled?('conversa_email_nova') &&
      Crm::Ai::CredentialResolver.new(account: message.account).configured?
  end

  # Sem o Google Tradutor ligado na conta: com ele, o Chatwoot traduz como sempre, na requisição.
  def self.em_segundo_plano?(message)
    aplica?(message) && !message.account.hooks.exists?(app_id: 'google_translate')
  end

  def self.idioma_do_painel?(idioma)
    IDIOMAS_DO_PAINEL.include?(idioma.to_s)
  end

  def initialize(message:, target_language:)
    @message = message
    @idioma = target_language.to_s.tr('_', '-')
  end

  def texto
    conteudo = original
    return if conteudo.blank? || conteudo.length > LIMITE_DE_CARACTERES

    resposta = cliente.create(model: Crm::Ai::Config::MODEL_SUMMARY, instructions: instrucoes, input: conteudo,
                              schema: ESQUEMA, reasoning_effort: 'low')
    JSON.parse(resposta[:text])['traducao'].to_s.presence
  rescue Crm::Ai::ResponsesClient::Error, JSON::ParserError => e
    Rails.logger.warn("[ConversaCanal::TraducaoDoEmail] message_id=#{@message.id} erro=#{e.class.name}")
    ChatwootExceptionTracker.new(e, account: @message.account).capture_exception
    nil
  end

  private

  def original
    email = (@message.content_attributes || {}).with_indifferent_access[:email] || {}
    email.dig(:html_content, :full).presence || email.dig(:text_content, :full).presence || @message.content.to_s
  end

  def instrucoes
    <<~PROMPT.strip
      Traduza o e-mail para o idioma de código #{@idioma}.
      Se vier HTML, devolva o MESMO HTML com só o texto traduzido: mantenha todas as tags, atributos, estilos, links
      e imagens exatamente como estão, na mesma ordem. Não traduza endereços de e-mail, URLs, nomes de pessoas e de
      empresas. Se vier texto puro, devolva texto puro. Não acrescente nada além da tradução.
    PROMPT
  end

  def cliente
    Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: @message.account).resolve,
                                 feature: 'traducao_email', account: @message.account)
  end
end
