# PONTO ÚNICO do lembrete de Atender fora da janela de 24 h (#1498). O WhatsApp só aceita modelo aprovado, e quem
# acha ou cria esse modelo é o Whatsapp::Templates::Garantir (#1518, sessão Modelos WhatsApp). Aqui só:
#   1. pede ao Garantir o modelo da finalidade do lembrete;
#   2. preenche os campos que ele devolve, na ordem dele, pelo catálogo de campos (TemplateFields::Resolver);
#   3. confere com o Whatsapp::Templates::DispatchCheck (aprovado e enviável), como a campanha faz;
#   4. devolve o metadata que o MessageSender já sabe mandar (template_params do upstream).
# Com o modelo em análise (o lembrete seguinte — no dia, depois — pede de novo), indisponível, com erro da Meta ou com
# campo sem valor, devolve "lembrar a equipe": o lembrete vira aviso na tela, e nada vai ao cliente. Nunca usa modelo
# fixo nem cria modelo por conta própria (quem cria é o Garantir).
# Só roda dentro de job (DueProcessor): a Meta pode levar uns 10 s.
class Crm::FollowUps::EnvioForaDaJanela
  Envio = Data.define(:status, :metadata, :motivo) do
    def enviar?
      status == :enviar
    end
  end
  FINALIDADE = :cobranca_vencimento
  # Só a Cobrança tem finalidade de modelo por enquanto; andamento e "deu certo?" fora da janela avisam a equipe.
  MOMENTOS = { 'payment_before' => :antes, 'payment_due' => :no_dia, 'payment_after' => :depois }.freeze
  PRONTO = 'pronto'.freeze
  # Regra nossa: lembrete é utilidade. Se a Meta classificar o modelo como outra coisa (MARKETING), nada vai ao
  # cliente — propaganda custa mais e precisa de decisão do Rodrigo; a equipe é avisada.
  CATEGORIA_PERMITIDA = 'UTILITY'.freeze
  # Só o número oficial (Channel::Whatsapp) manda modelo da Meta.
  CANAL_OFICIAL = 'Channel::Whatsapp'.freeze
  # O DispatchCheck conversa com campanha; aqui só precisa do id (para o log) e dos template_params.
  Conferencia = Data.define(:id, :template_params)

  # O motivo em linguagem simples, para o aviso que a equipe recebe no lugar da mensagem ao cliente.
  # "modelo_indisponivel:recusado" -> "recusado"; "modelo_em_analise" -> "em_analise"; o resto como veio.
  def self.aviso(motivo)
    texto = motivo.to_s
    chave = texto.include?(':') ? texto.split(':', 2).last : texto.delete_prefix('modelo_')
    # "send_failed_3", "unverified_quote_2": o número no fim é a tentativa.
    chave = chave.split('_')[0...-1].join('_') if chave.start_with?('send_failed_', 'unverified_quote_')
    detalhe = I18n.t("crm.service_reminders.aviso.#{chave}", default: '')
    [I18n.t('crm.service_reminders.aviso.titulo'), detalhe.presence].compact.join(' ')
  end

  def initialize(follow_up:, card:)
    @follow_up = follow_up
    @card = card
  end

  # -> Envio
  def call
    impedimento = motivo_para_nao_tentar
    return lembrar(impedimento) if impedimento

    modelo = garantir(momento)
    return lembrar(["modelo_#{modelo[:status]}", modelo[:motivo]].compact.join(':')) unless modelo[:status].to_s == PRONTO

    preparar(modelo)
  rescue StandardError => e
    # Meta fora ou lenta: avisa a equipe em vez de repetir a cada minuto dentro da trava do follow-up.
    Rails.logger.warn("[crm][envio_fora_da_janela] follow_up_id=#{@follow_up.id} #{e.class.name}: #{e.message.to_s[0, 160]}")
    lembrar('meta_fora')
  end

  private

  def motivo_para_nao_tentar
    return 'sem_finalidade_de_modelo' if momento.nil?

    'canal_sem_modelo_oficial' unless inbox&.channel_type == CANAL_OFICIAL
  end

  def momento
    MOMENTOS[@follow_up.metadata.to_h['kind'].to_s]
  end

  def garantir(momento)
    # idioma: nil sempre (= pt_BR): só há modelos prontos em pt_BR; o locale da conta ('en' por padrão) não teria modelo.
    Whatsapp::Templates::Garantir.call(inbox: inbox, finalidade: FINALIDADE, momento: momento,
                                       com_valor: @card.value_cents.to_i.positive?, idioma: nil)
                                 .to_h.with_indifferent_access
  end

  def preparar(modelo)
    return lembrar('categoria_propaganda') unless utilidade?(modelo[:categoria])

    corpo = campos(modelo[:campos].to_h)
    return lembrar('campo_sem_valor') if corpo.nil?

    template_params = { 'name' => modelo[:nome].to_s, 'language' => modelo[:idioma].to_s,
                        'category' => modelo[:categoria].to_s, 'processed_params' => { 'body' => corpo } }
    veredito = conferir(template_params)
    return lembrar("modelo_#{veredito.reason_code}") unless veredito.ok?
    return lembrar('categoria_propaganda') unless categoria_da_meta_ok?(veredito.template)

    Envio.new(status: :enviar, motivo: nil, metadata: metadata_de_envio(template_params, veredito.template))
  end

  def metadata_de_envio(template_params, modelo_da_meta)
    {
      'template_name' => template_params['name'], 'template_language' => template_params['language'],
      'template_category' => template_params['category'].downcase,
      'template_params_category' => template_params['category'],
      'template_processed_params' => template_params['processed_params'],
      'message_body' => texto_do_modelo(modelo_da_meta, template_params['processed_params']['body'])
    }
  end

  # O texto que o cliente recebe, para o histórico da conversa: o corpo do modelo com os campos no lugar.
  def texto_do_modelo(modelo_da_meta, corpo)
    componentes = modelo_da_meta.is_a?(Hash) ? Array(modelo_da_meta['components']) : []
    texto = componentes.find { |item| item.is_a?(Hash) && item['type'].to_s.casecmp?('BODY') }&.dig('text').to_s
    return @follow_up.title.to_s if texto.blank?

    corpo.reduce(texto) { |atual, (posicao, valor)| atual.gsub("{{#{posicao}}}", valor.to_s) }
  end

  # Na ordem que o Garantir devolve ('1' => 'cliente.primeiro_nome', ...), nunca por posição fixa, e com o valor já
  # formatado pelo catálogo (TemplateFields::Resolver). Campo sem valor (ou que o catálogo não conhece) não manda
  # nada: um modelo pela metade confunde o cliente.
  def campos(mapa)
    resolver = TemplateFields::Resolver.for_card(@card)
    mapa.each_with_object({}) do |(posicao, chave), corpo|
      valor = resolver.value(chave)
      return nil if valor.blank?

      corpo[posicao.to_s] = valor
    end
  end

  def conferir(template_params)
    Whatsapp::Templates::DispatchCheck.new(Conferencia.new(id: "follow_up:#{@follow_up.id}", template_params: template_params),
                                           channel: inbox.channel).call
  end

  def utilidade?(categoria)
    categoria.to_s.upcase == CATEGORIA_PERMITIDA
  end

  # A conferência relê o modelo na Meta; se a categoria mudou desde o Garantir, vale a da Meta.
  def categoria_da_meta_ok?(modelo_da_meta)
    categoria = modelo_da_meta.is_a?(Hash) ? modelo_da_meta['category'] : nil
    categoria.blank? || utilidade?(categoria)
  end

  def inbox
    @follow_up.conversation&.inbox
  end

  def lembrar(motivo)
    Envio.new(status: :lembrar_equipe, metadata: {}, motivo: motivo)
  end
end
