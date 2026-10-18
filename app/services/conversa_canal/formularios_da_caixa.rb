# Formulários (WhatsApp Flows) aprovados da conta do WhatsApp oficial, para o "+" da conversa (#1702). A Meta guarda os
# formulários na conta do WhatsApp Business (WABA) da caixa; só os publicados podem ser enviados. Para mandar, o envio do
# #1473 (`RichMessages::Types::Flow`) pede a primeira tela: ela sai do JSON do formulário, que a Meta entrega por link.
#
# Cuidados (revisão do #1702): o id do formulário só serve se for um dos publicados desta caixa (nada de montar URL da
# Graph com texto livre); o JSON só é baixado de endereço https da Meta, sem seguir redirecionamento e com teto de
# tamanho; erro de rede, resposta fora do formato e recusa da Meta viram frase nossa, nunca 500. A lista fica num cache
# curto por caixa e conta do WhatsApp (a troca de número muda a conta e, com ela, a chave do cache).
class ConversaCanal::FormulariosDaCaixa
  VERSAO = 'v22.0'.freeze
  TEMPO = 10
  PUBLICADO = 'PUBLISHED'.freeze
  POR_PAGINA = 100
  CACHE = 5.minutes
  TETO_DO_JSON = 2.megabytes
  DOMINIOS_DA_META = %w[fbsbx.com fbcdn.net facebook.com whatsapp.net].freeze
  SEM_PERMISSAO = [401, 403].freeze

  class Falha < StandardError; end

  def initialize(inbox)
    @canal = inbox.channel
  end

  # [{ id, nome, categorias }]
  def lista
    raise Falha, I18n.t('conversa_canal.formularios.sem_conta') if conta_whatsapp.blank?

    Rails.cache.fetch(['conversa_canal/formularios', @canal.id, conta_whatsapp], expires_in: CACHE) { lista_da_meta }
  end

  # A tela em que o formulário abre (a primeira do JSON publicado). Só para formulário publicado desta caixa.
  def primeira_tela(flow_id)
    raise Falha, I18n.t('conversa_canal.formularios.nao_encontrado') unless lista.any? { |formulario| formulario[:id] == flow_id.to_s }

    tela = Array(baixar_json(endereco_do_json(flow_id))['screens']).first
    (tela.is_a?(Hash) && tela['id'].presence) || raise(Falha, I18n.t('conversa_canal.formularios.sem_json'))
  end

  private

  def endereco_do_json(flow_id)
    ativos = pedir("#{base}/#{flow_id}/assets")
    Array(ativos['data']).find { |ativo| ativo.is_a?(Hash) && ativo['asset_type'] == 'FLOW_JSON' }&.dig('download_url')
  end

  def lista_da_meta
    corpo = pedir("#{base}/#{conta_whatsapp}/flows", fields: 'id,name,status,categories', limit: POR_PAGINA)
    Array(corpo['data'])
      .select { |formulario| formulario.is_a?(Hash) && formulario['status'] == PUBLICADO }
      .map { |formulario| { id: formulario['id'].to_s, nome: formulario['name'], categorias: Array(formulario['categories']) } }
  end

  def pedir(url, query = {})
    resposta = HTTParty.get(url, query: query, headers: { 'Authorization' => "Bearer #{@canal.provider_config['api_key']}" },
                                 timeout: TEMPO)
    recusada(resposta) unless resposta.success?
    objeto(resposta.body)
  rescue *Autonomia::Prospecting::GoogleErrorMessage::NETWORK_ERRORS => e
    Rails.logger.warn("[ConversaCanal::Formularios] channel_id=#{@canal.id} erro=#{e.class.name}")
    raise Falha, I18n.t('conversa_canal.formularios.meta_fora')
  end

  # O código da Meta vai para o log (campos estruturados, sem token) e a pessoa lê uma frase.
  def recusada(resposta)
    erro = objeto_ou_vazio(resposta.body)['error'].to_h
    Rails.logger.warn("[ConversaCanal::Formularios] channel_id=#{@canal.id} status=#{resposta.code} code=#{erro['code']} " \
                      "subcode=#{erro['error_subcode']} fbtrace_id=#{erro['fbtrace_id']}")
    chave = SEM_PERMISSAO.include?(resposta.code) || erro['code'].to_i == 200 ? 'sem_permissao' : 'meta_recusou'
    raise Falha, I18n.t("conversa_canal.formularios.#{chave}")
  end

  def baixar_json(endereco)
    raise Falha, I18n.t('conversa_canal.formularios.sem_json') unless endereco_da_meta?(endereco)

    resposta = HTTParty.get(endereco, timeout: TEMPO, follow_redirects: false)
    raise Falha, I18n.t('conversa_canal.formularios.sem_json') unless resposta.success? && resposta.body.to_s.bytesize <= TETO_DO_JSON

    objeto(resposta.body)
  rescue *Autonomia::Prospecting::GoogleErrorMessage::NETWORK_ERRORS => e
    Rails.logger.warn("[ConversaCanal::Formularios] channel_id=#{@canal.id} download erro=#{e.class.name}")
    raise Falha, I18n.t('conversa_canal.formularios.meta_fora')
  end

  def endereco_da_meta?(endereco)
    uri = URI.parse(endereco.to_s)
    host = uri.host.to_s.downcase
    uri.scheme == 'https' && DOMINIOS_DA_META.any? { |dominio| host == dominio || host.end_with?(".#{dominio}") }
  rescue URI::InvalidURIError
    false
  end

  def objeto(corpo)
    json = JSON.parse(corpo.to_s)
    raise Falha, I18n.t('conversa_canal.formularios.meta_recusou') unless json.is_a?(Hash)

    json
  rescue JSON::ParserError
    raise Falha, I18n.t('conversa_canal.formularios.meta_recusou')
  end

  def objeto_ou_vazio(corpo)
    json = JSON.parse(corpo.to_s)
    json.is_a?(Hash) ? json : {}
  rescue JSON::ParserError
    {}
  end

  def base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com') + "/#{VERSAO}"
  end

  def conta_whatsapp
    @canal.provider_config['business_account_id']
  end
end
