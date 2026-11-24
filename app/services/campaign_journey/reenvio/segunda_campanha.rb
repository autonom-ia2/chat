# #3101 (D1): cria a campanha da segunda mensagem pelos mesmos criadores da jornada, no mesmo canal da primeira, com o
# público só de quem vai receber (CampaignJourney::Reenvio::Publico), o nome "<nome> · segunda mensagem", a mesma caixa
# e o mesmo remetente, e o melhor horário se a primeira tinha. Ela sai como qualquer campanha: agora, passando pelo
# limite, pelo intervalo e pelo horário da conta (o Porteiro).
# - WhatsApp Oficial: o modelo e as ligações guardados na criação da primeira (o template_params da tela, §3.1), com os
#   textos padrão da primeira para as variáveis de mesmo nome;
# - SMS e WhatsApp API: o texto, com os textos padrão da primeira dos campos que ele usa;
# - E-mail (D3): o mesmo conteúdo com o assunto novo. O e-mail nasce rascunho; aqui ele já fica agendado, e o agendador
#   do e-mail confere tudo de novo antes de mandar (EmailCampaigns::Scheduler). Agenda com uma folga para a conferência
#   dos endereços (EmailCampaigns::RecipientPreflightJob, que a sincronização do público põe na fila) rodar antes.
# Devolve a campanha nova, ou nil quando nenhuma linha do público serve (a varredura grava sem_ninguem).
class CampaignJourney::Reenvio::SegundaCampanha
  FOLGA_DO_EMAIL = 15.minutes
  # O nome da primeira cabe cortado, para o nome novo caber no da WhatsApp API (120).
  MAXIMO_DO_NOME = 100

  def initialize(campanha, opcoes)
    @campanha = campanha
    @opcoes = opcoes
    @mensagem = opcoes.reenvio_mensagem.to_h
    @link = CampaignAudienceLink.for_campaign(campanha)
  end

  def criar!(contact_ids)
    raise CampaignJourney::Reenvio::Invalido, 'reenvio_sem_publico' if @link&.campaign_import.nil?

    @publico = CampaignJourney::Reenvio::Publico.copiar(@link.campaign_import, contact_ids, nome: titulo)
    return if @publico.nil?

    nova = criar_no_canal
    Autonomia::MelhorHorario.guardar!(nova, Autonomia::MelhorHorario.ligado?(@campanha))
    nova
  end

  private

  def criar_no_canal
    case CampaignJourney::Reenvio.canal_de(@campanha)
    when 'email' then email
    when 'whatsapp_api' then whatsapp_api
    when 'sms' then sms
    else whatsapp_cloud
    end
  end

  def conta
    @campanha.account
  end

  def titulo
    nome = @campanha.is_a?(EmailCampaign) ? @campanha.name : @campanha.title
    I18n.t('campaign_import.segunda_mensagem', nome: nome.to_s.first(MAXIMO_DO_NOME), locale: conta.locale)
  end

  def whatsapp_cloud
    CampaignJourney::WhatsappCampaignCreator.new(
      account: conta, campaign_import: @publico, channel: CampaignJourney::WhatsappCampaignCreator::CHANNEL, sender: @campanha.sender,
      attributes: { title: titulo, inbox_id: @campanha.inbox_id, template_params: @mensagem['template_params'],
                    variable_bindings: @mensagem['ligacoes'],
                    variable_defaults: CampaignJourney::Reenvio.padroes_das_chaves(@link, @mensagem['ligacoes'].to_h.keys) }
    ).perform
  end

  def sms
    texto = @mensagem['texto']
    CampaignJourney::SmsCampaignCreator.new(
      account: conta, campaign_import: @publico, channel: CampaignJourney::SmsCampaignCreator::CHANNEL, sender: @campanha.sender,
      attributes: { title: titulo, inbox_id: @campanha.inbox_id, message: texto,
                    variable_defaults: CampaignJourney::Reenvio.padroes(@link, texto) }
    ).perform
  end

  def whatsapp_api
    texto = @mensagem['texto']
    params = ActionController::Parameters.new(
      title: titulo, inbox_id: @campanha.inbox_id, message_body: texto, scheduled_at: nil,
      variable_defaults: CampaignJourney::Reenvio.padroes(@link, texto)
    )
    CampaignJourney::WhatsappApiCampaignCreator.new(account: conta, user: @campanha.created_by, campaign_import: @publico,
                                                    params: params).perform
  end

  def email
    nova = CampaignJourney::EmailCampaignCreator.new(account: conta, campaign_import: @publico, attributes: atributos_do_email).perform
    nova.update!(body_html: @campanha.body_html, body_mjml: @campanha.body_mjml, reply_to: @campanha.reply_to)
    nova.with_delivery_lock { nova.update!(status: :scheduled, scheduled_at: FOLGA_DO_EMAIL.from_now) }
    nova
  end

  def atributos_do_email
    {
      title: titulo, delivery_mode: @campanha.delivery_mode, sender_identity_id: @campanha.sender_identity_id,
      sender_inbox_id: @campanha.sender_inbox_id, from_name: @campanha.from_name, from_email: @campanha.from_email,
      reply_to_inbox_id: @campanha.reply_to_inbox_id, subject: @mensagem['assunto'], preheader: @campanha.preheader
    }
  end
end
