# #3101 (F5 do épico #3095, §4.3 do desenho): "Mandar de novo" — uma segunda mensagem, alguns dias depois do fim do
# envio da primeira, para quem recebeu e não respondeu (ou, no WhatsApp Oficial, não leu). Decisões do Rodrigo (23/11):
# - D1: a segunda mensagem é uma campanha nova, criada sozinha, do mesmo canal, com um público só de quem sobrou, com o
#   nome "<nome> · segunda mensagem", a caixa, o remetente e o melhor horário da primeira
#   (CampaignJourney::Reenvio::SegundaCampanha);
# - D2: "quem nem leu" só no WhatsApp Oficial (campaign_recipients.read_at); nos outros canais é recusado;
# - D3: no e-mail, o mesmo conteúdo com outro assunto.
#
# A escolha fica nas opções de envio da campanha (Autonomia::CampanhaOpcoesDeEnvio, colunas reenvio_*), gravada na
# criação (ou, no e-mail, no PUT email_medicoes, logo antes de enviar). Situação (`reenvio_status`): aguardando, depois
# enviado, sem_ninguem, cancelado (a primeira foi editada, cancelada ou apagada) ou falhou (a campanha nova foi recusada;
# o motivo vai para o log). `reenvio_em` fica nulo até a primeira terminar; aí a varredura grava o fim do envio mais os
# dias (CampaignJourney::Reenvio::Varredura).
#
# `reenvio_mensagem` por canal:
# - whatsapp_cloud: { modelo_id, template_params, ligacoes } — template_params montado pela tela com o mesmo
#   buildTemplateParams da primeira mensagem; ligacoes no formato de variable_bindings (CampaignJourney::VariableBindings);
# - sms e whatsapp_api: { texto };
# - email: { assunto }.
class CampaignJourney::Reenvio
  class Invalido < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  QUEM = %w[nao_respondeu nao_leu].freeze
  NAO_LEU = 'nao_leu'.freeze
  DIAS = [1, 2, 3, 5, 7].freeze
  AGUARDANDO = 'aguardando'.freeze
  ENVIADO = 'enviado'.freeze
  SEM_NINGUEM = 'sem_ninguem'.freeze
  CANCELADO = 'cancelado'.freeze
  FALHOU = 'falhou'.freeze
  # O mesmo teto da tela (reenvio.js, MAXIMO_DO_TEXTO).
  MAXIMO_DO_TEXTO = 1000
  MAXIMO_DO_ASSUNTO = 250
  DESLIGADO = { reenvio_quem: nil, reenvio_dias: nil, reenvio_mensagem: nil, reenvio_status: nil, reenvio_em: nil }.freeze

  # 'whatsapp_cloud', 'sms', 'whatsapp_api' ou 'email': o canal da jornada de uma campanha.
  def self.canal_de(campanha)
    case campanha
    when EmailCampaign then 'email'
    when WhatsappApiCampaign then 'whatsapp_api'
    else CampaignJourney::CampaignMarks.sms_inbox?(campanha.inbox) ? 'sms' : 'whatsapp_cloud'
    end
  end

  # `dados`: { reenvio_quem, reenvio_dias, reenvio_mensagem } do pedido. Sem `reenvio_quem`, desliga (a revisão manda o
  # estado inteiro a cada vez). Recusa com Invalido; quem chama está numa transação e a campanha volta junto.
  def self.guardar!(campanha, dados)
    dados = dados.to_h.with_indifferent_access
    opcoes = Autonomia::CampanhaOpcoesDeEnvio.find_or_initialize_by(campanha: campanha)
    return if opcoes.new_record? && dados[:reenvio_quem].blank?

    escolha = dados[:reenvio_quem].blank? ? DESLIGADO : new(campanha).conferir(dados)
    opcoes.update!(account_id: campanha.account_id, **escolha)
  end

  # A primeira foi editada antes de a segunda sair: a segunda não sai mais (CampaignJourney::Reenvio::Cancelavel).
  def self.cancelar!(campanha)
    Autonomia::CampanhaOpcoesDeEnvio.where(campanha: campanha, reenvio_status: AGUARDANDO)
                                    .update_all(reenvio_status: CANCELADO, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Os textos padrão da primeira mensagem, só dos campos que a segunda usa (SMS e WhatsApp API).
  def self.padroes(link, texto)
    padroes_das_chaves(link, WhatsappApiCampaigns::TemplateRenderer.variables_in(texto))
  end

  # Os textos padrão da primeira mensagem para as variáveis de mesmo nome da segunda (no WhatsApp Oficial, as chaves do
  # modelo, como '1'): guardados no link da primeira (CampaignJourney::WhatsappCampaignCreator#link_attributes) e usados
  # quando a pessoa não tem o valor (CampaignJourney::VariableBindings#resolve).
  def self.padroes_das_chaves(link, chaves)
    link&.variable_defaults.to_h.transform_keys(&:to_s).slice(*chaves.map(&:to_s))
  end

  def initialize(campanha)
    @campanha = campanha
    @canal = self.class.canal_de(campanha)
  end

  def conferir(dados)
    quem = dados[:reenvio_quem].to_s
    raise Invalido, 'reenvio_quem_invalido' unless QUEM.include?(quem)
    raise Invalido, 'reenvio_quem_invalido' if quem == NAO_LEU && @canal != 'whatsapp_cloud'
    raise Invalido, 'reenvio_dias_invalido' unless DIAS.include?(dados[:reenvio_dias].to_i)

    { reenvio_quem: quem, reenvio_dias: dados[:reenvio_dias].to_i, reenvio_mensagem: mensagem(dados[:reenvio_mensagem].to_h),
      reenvio_status: AGUARDANDO, reenvio_em: nil, reenvio_campanha_type: nil, reenvio_campanha_id: nil }
  end

  private

  def mensagem(dados)
    case @canal
    when 'email' then { 'assunto' => assunto(dados) }
    when 'whatsapp_cloud' then CampaignJourney::Reenvio::Modelo.new(@campanha).conferir(dados)
    else { 'texto' => texto(dados) }
    end
  end

  def assunto(dados)
    assunto = dados['assunto'].to_s.strip
    raise Invalido, 'reenvio_sem_assunto' if assunto.empty?
    raise Invalido, 'reenvio_assunto_longo' if assunto.size > MAXIMO_DO_ASSUNTO

    assunto
  end

  # SMS e WhatsApp API usam a mesma gramática de campos (CampaignJourney::SmsMessage).
  def texto(dados)
    texto = dados['texto'].to_s.strip
    raise Invalido, 'reenvio_sem_texto' if texto.empty?
    raise Invalido, 'reenvio_texto_longo' if texto.size > MAXIMO_DO_TEXTO

    link = CampaignAudienceLink.for_campaign(@campanha)
    CampaignJourney::SmsMessage.new(texto, campaign_import: link&.campaign_import, defaults: self.class.padroes(link, texto)).validate!
    texto
  rescue CampaignJourney::SmsMessage::Error => e
    raise Invalido, "reenvio_#{e.message}"
  end
end
