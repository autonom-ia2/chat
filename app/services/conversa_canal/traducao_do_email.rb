# Tradução de e-mail pela IA da conta (#1786), para quem não ligou o Google Tradutor (decisão do Rodrigo, 18/10:
# "IA da conta, Google se houver"). Mesma chave do ditado e do CRM (Crm::Ai::CredentialResolver). Traduz o HTML do
# e-mail mantendo a marcação (tabelas, listas, links, imagens), para a tela mostrar a tradução com a mesma cara.
# Só para a conversa de e-mail nova (chave `conversa_email_nova`); os outros canais seguem só com o Google.
class ConversaCanal::TraducaoDoEmail
  # E-mail muito grande (newsletter com HTML pesado) não vai para a IA: custo e tempo sem retorno.
  LIMITE_DE_CARACTERES = 60_000
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
