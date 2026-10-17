# Encaminhar mensagens (#1702), como no WhatsApp: o atendente marca uma ou mais mensagens da conversa e escolhe até 5
# conversas de destino. Em cada destino nasce uma cópia ENVIADA pela empresa, pelo caminho de sempre
# (Messages::MessageBuilder -> SendReplyJob), com `content_attributes.forwarded = true` (o balão desenha "Encaminhada")
# e `forwarded_from = { conversation_id (display_id), message_id }`. O que cada mensagem vira está em
# ConversaCanal::CopiaEncaminhada (anexo reaproveita o blob, sem baixar de novo).
#
# Regras:
# - limite de 5 destinos por vez, o do WhatsApp (até cinco conversas de uma vez; Central de Ajuda, "Sobre os limites
#   de encaminhamento": https://faq.whatsapp.com/1053543185312573). O teto de 30 mensagens por vez é nosso.
# - nota privada, atividade, apagada, não suportada, com falha, de visualização única (o app não deixa encaminhar) e
#   formato sem envio (formulário, CSAT, e-mail) não se encaminham: o pedido inteiro é recusado (422).
# - destino fora da janela de 24 h na API oficial (Conversation#can_reply?, que já conta o Híbrido): não sai mensagem
#   livre, então a cópia não é criada e o destino volta com "fora da janela: use um modelo".
# - cada destino é tudo ou nada (transação): se uma cópia não grava, nenhuma daquele destino fica.
# - só pessoa (User): encaminhamento automatizado é sinal de spam para o WhatsApp; robô e automação são recusados.
# Quem pode o quê é do controller: ver a origem e responder em cada destino (ConversationPolicy#show?).
# Caixa WAHA: sai a cópia pelo conector, como toda mensagem. O WAHA tem POST /api/forwardMessage (rótulo nativo); quem
# pluga o envio nativo é o WhatsApp Híbrido, achando a original por `forwarded_from`.
class ConversaCanal::Encaminhamento
  LIMITE_DE_DESTINOS = 5
  LIMITE_DE_MENSAGENS = 30
  TIPOS_DE_CONTEUDO = %w[text sticker].freeze

  class Recusa < StandardError; end

  def initialize(origem:, message_ids:, destinos:, user:)
    @origem = origem
    @message_ids = Array(message_ids).filter_map { |id| Integer(id.to_s, exception: false) }.uniq
    @destinos = Array(destinos).uniq
    @user = user
  end

  # -> [{ conversation_id:, ok:, erro: }] na ordem dos destinos. Levanta Recusa com a frase para a tela.
  def perform
    validar!
    @destinos.map { |destino| encaminhar_para(destino) }
  end

  private

  def validar!
    validar_quantidades!
    recusar!(:mensagem_nao_encontrada) if mensagens.size != @message_ids.size
    recusar!(:nao_encaminhavel) unless mensagens.all? { |mensagem| encaminhavel?(mensagem) }
  end

  # Antes de buscar: pedido grande demais nem chega ao banco.
  def validar_quantidades!
    recusar!(:so_pessoa) unless @user.is_a?(User)
    recusar!(:sem_mensagem) if @message_ids.empty?
    recusar!(:sem_destino) if @destinos.empty?
    recusar!(:destinos_demais, limite: LIMITE_DE_DESTINOS) if @destinos.size > LIMITE_DE_DESTINOS
    recusar!(:mensagens_demais, limite: LIMITE_DE_MENSAGENS) if @message_ids.size > LIMITE_DE_MENSAGENS
  end

  def mensagens
    @mensagens ||= @origem.messages.where(id: @message_ids).includes(attachments: { file_attachment: :blob }).to_a
  end

  def encaminhavel?(mensagem)
    tipo_encaminhavel?(mensagem) && !marcada_como_fora?(mensagem) && copia(mensagem).envios.any?
  end

  # Do cliente ou da empresa, nunca nota, atividade, falha ou formato sem envio (formulário, CSAT, e-mail).
  def tipo_encaminhavel?(mensagem)
    return false if mensagem.private? || mensagem.failed?

    (mensagem.incoming? || mensagem.outgoing?) && TIPOS_DE_CONTEUDO.include?(mensagem.content_type)
  end

  def marcada_como_fora?(mensagem)
    atributos = mensagem.content_attributes.to_h
    return true if atributos.values_at('deleted', 'deleted_by_contact_at', 'is_unsupported').any?(&:present?)

    mensagem.attachments.any? { |anexo| ConversaCanal::VisualizacaoUnica.marcado?(anexo) }
  end

  def copia(mensagem)
    @copias ||= {}
    @copias[mensagem.id] ||= ConversaCanal::CopiaEncaminhada.new(mensagem)
  end

  def encaminhar_para(destino)
    return resultado(destino, erro: frase(:fora_da_janela)) unless destino.can_reply?

    ActiveRecord::Base.transaction do
      mensagens.each { |mensagem| copiar(mensagem, destino) }
    end
    resultado(destino)
  # Qualquer falha fica naquele destino (transação desfeita); os outros seguem e cada um volta com o seu resultado.
  rescue StandardError => e
    Rails.logger.warn("[conversa_canal][encaminhar] origem=#{@origem.id} destino=#{destino.id} #{e.class}")
    resultado(destino, erro: frase(:falhou))
  end

  def copiar(mensagem, destino)
    marca = { 'forwarded' => true, 'forwarded_from' => { 'conversation_id' => @origem.display_id, 'message_id' => mensagem.id } }
    copia(mensagem).envios.each do |envio|
      atributos = envio.fetch(:content_attributes, {}).merge(marca)
      Messages::MessageBuilder.new(@user, destino, envio.merge(content_attributes: atributos).with_indifferent_access).perform
    end
  end

  def resultado(destino, erro: nil)
    { conversation_id: destino.display_id, ok: erro.nil?, erro: erro }
  end

  def frase(codigo, **)
    I18n.t("conversa_canal.encaminhar.#{codigo}", **)
  end

  def recusar!(codigo, **)
    raise Recusa, frase(codigo, **)
  end
end
