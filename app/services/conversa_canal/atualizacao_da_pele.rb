# Uma atualização de mensagem que só mexe em marcas da conversa com a cara do canal (#1702): reação, lida enviada,
# prévia de link, áudio ouvido, apagada pelo cliente. Ela existe para a tela; quem age sobre `message_updated` não
# deve vê-la como mensagem mudada:
# - o robô (AgentBot / n8n) responderia de novo, com IA paga (revisão dos Agentes IA, 16/10);
# - o conector WAHA (webhook da caixa API) trata `message_updated` com a chave `external_error` presente, mesmo nula,
#   como pedido de reenvio e MANDA A MENSAGEM DE NOVO ao cliente (WAHA 2026.9.2,
#   src/apps/chatwoot/api/chatwoot.webhook.controller.ts, aviso do WhatsApp Híbrido em 16/10).
# A tela continua recebendo o evento pelo broadcast de sempre; os webhooks da conta também.
module ConversaCanal::AtualizacaoDaPele
  # Da segunda linha em diante, gravadas pelo conector WAHA do #1709 (votos, respostas de evento, histórico de edição,
  # aviso de visualização única resolvido). Lista única com o Waha::RichNative::SilentUpdate do #1709.
  CHAVES = %w[reactions read_receipt_sent_at link_preview played_at deleted_by_contact_at
              poll_votes event_responses edit_history edited_at c2y_hidden view_once_resolved_by].freeze
  COLUNAS_PERMITIDAS = %w[content_attributes updated_at].freeze

  module_function

  # Só com a pele ligada na conta: sem ela, robô e webhooks recebem tudo como na main (inclusive as marcas gravadas
  # pelo WhatsApp Híbrido, que tem o próprio silêncio, Waha::RichNative::SilentUpdate).
  # Na caixa do Instagram vale a chave da conversa do Instagram (#2113), que grava as mesmas marcas (reação) sem
  # depender da pele do WhatsApp.
  def silenciar?(message, mudancas)
    message.present? && marcas_ligadas?(message) && so_da_pele?(mudancas)
  end

  def marcas_ligadas?(message)
    ConversaCanal::Pele.ligada?(message.account) || instagram_ligado?(message)
  end

  def instagram_ligado?(message)
    message.inbox.present? && message.inbox.instagram? && message.account.feature_enabled?(Instagram::ReacaoDoCliente::FLAG)
  end

  # `previous_changes` do evento: { 'coluna' => [antes, depois] }.
  def so_da_pele?(mudancas)
    return false unless mudancas.respond_to?(:keys)

    colunas = mudancas.keys.map(&:to_s)
    return false unless colunas.include?('content_attributes') && (colunas - COLUNAS_PERMITIDAS).empty?

    chaves = chaves_mudadas(*mudancas.with_indifferent_access[:content_attributes])
    chaves.any? && (chaves - CHAVES).empty?
  end

  # Valor que não é Hash (ex.: JSON gravado como texto) não é atualização da pele: segue o caminho de sempre.
  def chaves_mudadas(antes, depois)
    antes ||= {}
    depois ||= {}
    return [] unless antes.is_a?(Hash) && depois.is_a?(Hash)

    antes = antes.stringify_keys
    depois = depois.stringify_keys
    (antes.keys | depois.keys).reject { |chave| antes[chave] == depois[chave] }
  end
end
