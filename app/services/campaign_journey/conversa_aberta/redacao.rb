# A ajuda para escrever a mensagem da conversa aberta (#1335): monta o pedido ao redator (`Ai::Redacao::Escrever`, canal
# `whatsapp_campanha`) com os campos do Público. O que a pessoa escreve vai como dado; nada vai ao log.
#
#   CampaignJourney::ConversaAberta::Redacao.new(account:, campaign_import:, categoria: 'MARKETING')
#     .call(objetivo: 'avisar da coleção nova', tom: 'curto')
#     .call(base: 'Oi, {{cliente.primeiro_nome}}!...', melhoria: 'mais_curta')
class CampaignJourney::ConversaAberta::Redacao
  FEATURE = 'campanha_redacao'.freeze
  CANAL = 'whatsapp_campanha'.freeze
  PROPOSITO = 'campanha para quem mandou mensagem para a empresa nas últimas 24 horas'.freeze
  TONS = %w[simpatico curto formal].freeze
  # O que a tela pede → o vocabulário do redator (comum.md); "mais simpática" é o tom.
  MELHORIAS = { 'mais_curta' => 'mais_curto', 'mais_clara' => 'mais_claro', 'mais_simpatica' => nil }.freeze
  TIPO_DO_MODELO = { 'MARKETING' => 'divulgacao', 'UTILITY' => 'servico' }.freeze
  MAX_PEDIDO = 500
  OPCOES = 2

  def initialize(account:, campaign_import:, categoria: nil)
    @account = account
    @campaign_import = campaign_import
    @categoria = categoria.to_s.upcase.presence
  end

  def call(objetivo: nil, resposta: nil, tom: nil, base: nil, melhoria: nil)
    melhoria = melhoria.to_s.presence_in(MELHORIAS.keys)
    Ai::Redacao::Escrever.call(
      account: @account, feature: FEATURE, canal: CANAL, proposito: PROPOSITO,
      limites: { max_chars: CampaignJourney::ConversaAberta::Texto::MAX_CHARS },
      chaves: { permitidas: CampaignJourney::ConversaAberta::Texto.chaves_permitidas(@campaign_import.extra_columns), obrigatorias: [] },
      tom: tom_de(tom, melhoria), base: melhoria && base.to_s.first(CampaignJourney::ConversaAberta::Texto::MAX_CHARS).presence,
      pedido: pedido_de(objetivo, resposta, melhoria), opcoes: OPCOES, contexto: { tipo_do_modelo: TIPO_DO_MODELO[@categoria] }
    )
  end

  private

  def tom_de(tom, melhoria)
    return 'simpatico' if melhoria == 'mais_simpatica'

    tom.to_s.presence_in(TONS)
  end

  # Modo criar: a frase da pessoa (e a resposta à pergunta do redator, se houver). Modo melhorar: as melhorias.
  def pedido_de(objetivo, resposta, melhoria)
    return { melhorias: [MELHORIAS[melhoria]].compact, observacao: nil } if melhoria

    [objetivo, resposta].map { |texto| texto.to_s.strip.first(MAX_PEDIDO) }.compact_blank.join("\n")
  end
end
