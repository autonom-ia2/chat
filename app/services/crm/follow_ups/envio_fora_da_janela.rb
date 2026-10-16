# Elo do Followup com o PONTO ÚNICO fora da janela de 24 h (Whatsapp::Templates::EnvioForaDaJanela, #1587). O WhatsApp só
# aceita modelo aprovado; quem acha, cria e confere o modelo é o ponto único. Aqui só:
#   1. traduz o follow-up para o tipo (cobrança: antes, no dia, depois; retorno) e usa o plano que o pré-voo gravou (#1624);
#   2. sem plano gravado, planeja sem criar (criar é do pré-voo, nunca do horário do envio);
#   3. preenche os campos que o plano pede, pelo catálogo (TemplateFields::Resolver) com os dados do card de agora;
#   4. pede o `enviar` (que NÃO envia) e devolve o metadata que o MessageSender já sabe mandar.
# Com o modelo em análise, indisponível, sem autorização, com erro da Meta ou com campo sem valor, devolve "lembrar a
# equipe": o lembrete vira aviso na tela, e nada vai ao cliente. Nunca usa modelo fixo nem cria modelo por conta própria.
# Só roda dentro de job (DueProcessor): a Meta pode levar uns 10 s.
class Crm::FollowUps::EnvioForaDaJanela
  Envio = Data.define(:status, :metadata, :motivo) do
    def enviar?
      status == :enviar
    end
  end
  Ponto = Whatsapp::Templates::EnvioForaDaJanela
  # Cobrança: o momento do lembrete é o tipo do ponto único.
  TIPOS = { 'payment_before' => 'cobranca_antes', 'payment_due' => 'cobranca_no_dia', 'payment_after' => 'cobranca_depois' }.freeze
  TIPO_RETORNO = 'retorno'.freeze
  # Regra nossa: lembrete de cobrança é utilidade. Se o modelo escolhido for MARKETING, nada vai ao cliente — propaganda
  # custa mais e precisa de decisão do Rodrigo; a equipe é avisada.
  CATEGORIA_PERMITIDA = 'UTILITY'.freeze
  # Só o número oficial (Channel::Whatsapp) manda modelo da Meta.
  CANAL_OFICIAL = 'Channel::Whatsapp'.freeze

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

  # O tipo do ponto único para este follow-up, ou nil quando ele não tem modelo (andamento e "deu certo?" fora da janela
  # avisam a equipe, como antes).
  def self.tipo_de(follow_up)
    metadata = follow_up.metadata.to_h
    return TIPOS[metadata['kind'].to_s] if metadata['source'] == Crm::FollowUps::ServiceReminderScheduler::SOURCE

    TIPO_RETORNO if metadata['source'] == Crm::FollowUps::CallbackScheduler::SOURCE
  end

  # plano: o do pré-voo, ou o que o chamador acabou de montar. Sem ele, planeja aqui, sem criar modelo.
  def initialize(follow_up:, card:, plano: nil)
    @follow_up = follow_up
    @card = card
    @plano = plano
  end

  # -> Envio
  def call
    impedimento = motivo_para_nao_tentar
    return lembrar(impedimento) if impedimento

    preparar(@plano || self.class.plano_gravado(@follow_up) || planejar)
  rescue StandardError => e
    # Meta fora ou lenta: avisa a equipe em vez de repetir a cada minuto dentro da trava do follow-up.
    Rails.logger.warn("[crm][envio_fora_da_janela] follow_up_id=#{@follow_up.id} #{e.class.name}: #{e.message.to_s[0, 160]}")
    lembrar('meta_fora')
  end

  # O plano que o pré-voo gravou para o horário de agora (nil se não houve ou se o horário mudou).
  def self.plano_gravado(follow_up)
    Crm::FollowUps::Preflight.marca_vigente(follow_up)&.dig('plano')
  end

  private

  def motivo_para_nao_tentar
    return 'sem_finalidade_de_modelo' if tipo.nil?

    'canal_sem_modelo_oficial' unless inbox&.channel_type == CANAL_OFICIAL
  end

  def tipo
    @tipo ||= self.class.tipo_de(@follow_up)
  end

  def cobranca?
    TIPOS.value?(tipo)
  end

  def planejar
    Ponto.planejar(inbox: inbox, tipo: tipo, com_valor: @card.value_cents.to_i.positive?, ja_recusado: !cobranca?,
                   contato: contato, criar: false)
  end

  def preparar(plano)
    plano = plano.to_h.deep_stringify_keys
    envio = Ponto.enviar(inbox: inbox, plano: plano, valores: valores(plano['campos'].to_h), contato: contato)
    return lembrar(envio.motivo) unless envio.enviar?
    return lembrar('categoria_propaganda') if cobranca? && propaganda?(envio.metadata['template_params_category'])

    Envio.new(status: :enviar, motivo: nil, metadata: envio.metadata)
  end

  # Posição -> valor do catálogo, com os dados do card de agora (valor e vencimento podem mudar até o horário). Chave que
  # o catálogo não conhece fica sem valor, e o ponto único não manda um modelo pela metade.
  def valores(campos)
    resolver = TemplateFields::Resolver.for_card(@card)
    campos.to_h { |posicao, chave| [posicao.to_s, resolver.value(chave)] }
  end

  def propaganda?(categoria)
    categoria.to_s.upcase != CATEGORIA_PERMITIDA
  end

  def contato
    @follow_up.conversation&.contact || @card.contact
  end

  def inbox
    @follow_up.conversation&.inbox
  end

  def lembrar(motivo)
    Envio.new(status: :lembrar_equipe, metadata: {}, motivo: motivo)
  end
end
