# Reenvia uma mensagem de modelo já enviada para outra conversa: o MESMO modelo aprovado, com os MESMOS valores (#1767,
# épico #1320). É o 2º caminho do encaminhamento fora das 24 h (o 1º, Híbrido, e a escolha ficam com quem chama, o
# Frontend geral, #1702). A Meta cobra a mensagem nova.
#
#   Whatsapp::Templates::ReenvioDoModelo.call(message_original: mensagem, destino: conversa, remetente: usuario)
#   # => { status: :criado, message: <Message nova na conversa de destino> }
#   #  | { status: :falhou, motivo: 'modelo_indisponivel' }   texto: ReenvioDoModelo.texto(motivo)
#
# - `:criado`: a mensagem foi criada e o envio, enfileirado (`SendReplyJob`, como todo envio). Se a Meta recusar depois,
#   a recusa aparece na própria mensagem (`status: failed` + `external_error`), como em qualquer envio da conversa.
# - A mensagem original pode ser de conversa, aviso do agendamento, follow-up ou envio fora da janela (todas guardam
#   `template_params`) ou de campanha (só `campaign_id`: os parâmetros daquela pessoa são remontados em `DaCampanha`).
# - Só barra o que a plataforma não aceita (decisão do Rodrigo, 17/10/2026: "ajudar, não travar"): outra conta, caixa
#   que não é do WhatsApp oficial, modelo que não está aprovado na caixa de destino ou em que os valores não cabem mais,
#   oferta vencida, formato que o envio não monta, arquivo que sumiu, produto esgotado, produtos com a flag
#   `whatsapp_campaign_products` desligada (como nos outros envios) e modelo de autenticação para destinatário sem
#   telefone (BSUID, `Whatsapp::AuthenticationTemplateGuard`, como no disparo). Categoria mudada não impede: vai a atual.
# - Confere o modelo NA CAIXA DE DESTINO como o disparo da campanha (`DispatchCheck` + lista da caixa). Como o disparo
#   (`CampaignPauses::WhatsappDispatchGate#keep_meta_version`), o modelo aprovado que a Meta devolveu vai para a lista da
#   caixa ANTES da decisão final: é a versão atual do modelo, vale mesmo se o reenvio parar depois.
# - Link de arquivo nosso (assinado, com prazo) é assinado de novo (`Midia`): nunca vai link vencido.
# - A mensagem nova leva `template_params` literal (os valores já estão preenchidos: o Liquid não roda de novo).
# - Nunca levanta: erro inesperado vira `erro`. Fala com a Meta (uma consulta do modelo; com produtos, o catálogo).
# - Log só com ids, nome do modelo e motivo: nada do texto nem dos valores do cliente.
class Whatsapp::Templates::ReenvioDoModelo
  MOTIVOS = %w[
    conta_diferente caixa_nao_oficial nao_e_modelo sem_parametros modelo_indisponivel modelo_mudou oferta_vencida
    formato_nao_suportado midia_indisponivel produto_indisponivel produtos_desligados nao_aceito_pela_meta erro
  ].freeze
  # Código do DispatchCheck -> motivo (os outros: modelo_indisponivel). Meta fora e sem lista guardada: tentar de novo.
  VEREDITOS = {
    'template_structure_changed' => 'modelo_mudou', 'template_offer_expired' => 'oferta_vencida',
    'template_format_unsupported' => 'formato_nao_suportado', 'templates_not_synced' => 'erro', 'template_unverifiable' => 'erro'
  }.freeze
  # O que vai da mensagem original para a nova (o resto de `template_params` é marca do envio de lá).
  CAMPOS = %w[name language namespace category processed_params].freeze
  PRODUTOS_FLAG = 'whatsapp_campaign_products'.freeze
  # O `DispatchCheck` conversa com campanha; aqui só precisa do id (para o log) e dos template_params.
  Conferencia = Data.define(:id, :template_params)

  def self.call(message_original:, destino:, remetente: nil)
    new(message_original: message_original, destino: destino, remetente: remetente).call
  end

  # Em duas etapas, para quem grava vários reenvios numa transação (encaminhamento, #1702): `conferir` fala com a Meta
  # FORA dela e devolve { status: :conferido, reenvio: } ou a falha; depois, dentro, `reenvio.criar_conferido` só grava.
  def self.conferir(message_original:, destino:, remetente: nil)
    new(message_original: message_original, destino: destino, remetente: remetente).conferir
  end

  def self.texto(motivo)
    I18n.t("whatsapp_templates.reenvio.motivos.#{motivo}")
  end

  def initialize(message_original:, destino:, remetente:)
    @original = message_original
    @destino = destino
    @remetente = remetente
  end

  def call
    conferido = conferir
    return conferido unless conferido[:status] == :conferido

    criar_conferido
  rescue StandardError => e
    erro_inesperado(e)
  end

  def conferir
    motivo = impedimento
    return falhou(motivo) if motivo

    params = parametros
    return falhou(@campanha ? @campanha.motivo : 'nao_e_modelo') if params.nil?

    conferir_params(params)
  rescue StandardError => e
    erro_inesperado(e)
  end

  # Só grava (sem Meta): levanta se a gravação falhar, para a transação de quem chama desfazer.
  def criar_conferido
    { status: :criado, message: criar(@conferidos) }
  end

  private

  def impedimento
    return 'conta_diferente' unless @original.account_id == @destino.account_id
    return 'caixa_nao_oficial' unless Whatsapp::Templates::MetaClient.supported?(@destino.inbox)

    nil
  end

  def channel
    @destino.inbox.channel
  end

  # Mensagem com `template_params` (conversa, agendamento, follow-up, fora da janela): cópia. De campanha: remontada.
  def parametros
    gravado = @original.additional_attributes.to_h['template_params']
    return gravado.to_h.deep_stringify_keys.slice(*CAMPOS).compact if gravado.is_a?(Hash) && gravado['name'].present?
    return if @original.additional_attributes.to_h['campaign_id'].blank?

    @campanha = DaCampanha.new(@original)
    @campanha.parametros
  end

  def conferir_params(params)
    veredito = conferencia(params)
    return falhou(VEREDITOS.fetch(veredito.reason_code, 'modelo_indisponivel'), params) unless veredito.ok?

    manter_versao_da_meta(veredito)
    params, motivo = completar(params, veredito.template)
    return falhou(motivo, params) if motivo
    return falhou('modelo_indisponivel', params) unless na_lista?(params)
    return falhou('nao_aceito_pela_meta', params) if autenticacao_recusada?(params)

    @conferidos = params
    { status: :conferido, reenvio: self }
  end

  def erro_inesperado(erro)
    Rails.logger.error("[whatsapp_templates][reenvio] original=#{@original&.id} destino=#{@destino&.id} erro=#{erro.class.name}")
    falhou('erro')
  end

  # Sem a categoria gravada: categoria mudada não impede o reenvio (a Meta aceita o mesmo modelo).
  def conferencia(params)
    Whatsapp::Templates::DispatchCheck.new(Conferencia.new(id: "reenvio:#{@original.id}", template_params: params.except('category')),
                                           channel: channel).call
  end

  def manter_versao_da_meta(veredito)
    return unless veredito.details.to_h[:lookup_source] == Whatsapp::Templates::DispatchCheck::META

    template = veredito.template
    Whatsapp::Templates::ChannelList.upsert!(channel, template, merge: true, only_existing: !template.key?('parameter_format'))
  rescue StandardError => e
    # A conferência da lista logo depois decide: o modelo pode já estar lá pelo sync.
    Rails.logger.error("[whatsapp_templates][reenvio] original=#{@original.id} meta_template_not_kept=#{e.class.name}")
  end

  # [params, nil] ou [params, motivo]: a categoria atual; os arquivos com link novo; na campanha, o que o disparo acrescenta.
  def completar(params, template)
    categoria = template.is_a?(Hash) ? template['category'].presence : nil
    params = params.merge('category' => categoria) if categoria
    return [params, 'produtos_desligados'] if produtos_desligados?(template)
    return completar_da_campanha(params, template) if @campanha

    processed = Midia.renovar(params['processed_params'], @destino.inbox)
    processed ? [params.merge('processed_params' => processed), nil] : [params, 'midia_indisponivel']
  end

  def completar_da_campanha(params, template)
    completo = @campanha.com_extras(params, template: template, inbox: @destino.inbox)
    completo ? [completo, nil] : [params, @campanha.motivo]
  end

  def produtos_desligados?(template)
    Whatsapp::Templates::ProductParams.kind(template).present? && !@destino.account.feature_enabled?(PRODUTOS_FLAG)
  end

  def na_lista?(params)
    Whatsapp::TemplateProcessorService.new(channel: channel, template_params: params).template_in_list?
  end

  def autenticacao_recusada?(params)
    Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: @destino.contact_inbox&.source_id.to_s,
                                              template_params: params).error.present?
  end

  def criar(params)
    message = Autonomia::LiteralMessageBuilder.new(
      @remetente, @destino,
      ActionController::Parameters.new(content: @original.content, private: false, message_type: 'outgoing', template_params: params,
                                       content_attributes: { reenvio_do_modelo: { mensagem_original_id: @original.id } }),
      literal_content: true, literal_template_params: true
    ).perform
    log("criado message=#{message.id}", params)
    message
  end

  def falhou(motivo, params = nil)
    log("falhou motivo=#{motivo}", params)
    { status: :falhou, motivo: motivo }
  end

  def log(resultado, params)
    modelo = params ? " modelo=#{params['name']}" : ''
    Rails.logger.info("[whatsapp_templates][reenvio] original=#{@original&.id} destino=#{@destino&.id}#{modelo} #{resultado}")
  end
end
