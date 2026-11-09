# G58 (#2779): o disparo do passo campanha com `publico: desta_execucao`. As guardas (gatilho da conta, quem ligou
# pode disparar, caixa oficial, flag, modelo pronto) já passaram no PassoDeCampanha; aqui só muda o público.
#
# Nada novo no envio: os contatos que a execução criou (ContatosDaExecucao) viram um Público de Campanhas
# (CampaignJourney::AudienceWriter, source 'automacao', com a automação e a execução nas opções), com a mesma linha da
# Prospecção (AudienceFromLeads.row_for). A Campanha sai pelo CampaignJourney::WhatsappCampaignCreator, ligada ao Público
# (CampaignAudienceLink), como a tela de Campanhas. O envio é o de todo Público (Whatsapp::OneoffCampaignService com
# CampaignJourney::AudienceContacts): recusa relida no envio e status por destinatário. Público e Campanha nascem juntos
# ou nenhum.
#
# Quem ligou é o dono do Público e o remetente da Campanha (`sender`): as mensagens saem com o nome dele na conversa,
# como no caminho das etiquetas. Se quem ligou não alcança os contatos (Acesso#alcanca?), a automação pausa
# (`sem_acesso`), em vez de pular toda semana como se ninguém tivesse sido criado.
#
# O registro guarda só ids e contagens. A recusa do writer ou do creator vira `campanha_recusada`, com o código no log.
class Autonomia::Automacao::CampanhaDaExecucao
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  SOURCE = 'automacao'.freeze
  CANAL = ::CampaignJourney::WhatsappCampaignCreator::CHANNEL

  def initialize(execucao:, passo:, caixa:, template_params:)
    @execucao = execucao
    @passo = passo
    @caixa = caixa
    @template_params = template_params
    @conta = execucao.account
    @contatos = ::Autonomia::Automacao::ContatosDaExecucao.new(execucao: execucao)
  end

  def disparar
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: {}) if @contatos.sem_alcance.any?
    return pulado('campanha_execucao_sem_contatos') if @contatos.dentro.empty?

    campanha = ActiveRecord::Base.transaction { criar_campanha(gravar_publico) }
    ::Campaigns::TriggerOneoffCampaignJob.perform_later(campanha)
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'campanha_id' => campanha.display_id, 'publico_id' => publico_id(campanha),
                                                   'contatos' => @contatos.dentro.size, 'fora' => @contatos.fora })
  rescue ::CampaignJourney::AudienceWriter::Error, ::CampaignJourney::AudienceCampaignCreator::Error => e
    codigo = e.respond_to?(:code) ? e.code : e.message
    Rails.logger.info("[automacao][campanha] publico da execucao recusado execucao=#{@execucao.id} codigo=#{codigo}")
    pulado('campanha_recusada')
  end

  private

  def gravar_publico
    opcoes = { 'automacao_id' => @execucao.automacao_id, 'execucao_id' => @execucao.id }
    linhas = @contatos.dentro.map { |contato| ::Autonomia::Prospecting::AudienceFromLeads.row_for(contato) }
    ::CampaignJourney::AudienceWriter.new(@conta, user: quem_ligou, source: SOURCE, options: opcoes)
                                     .perform(nome_do_publico, linhas)
  end

  def criar_campanha(publico)
    ::CampaignJourney::WhatsappCampaignCreator.new(account: @conta, campaign_import: publico, channel: CANAL, sender: quem_ligou,
                                                   attributes: atributos_da_campanha).perform
  end

  def atributos_da_campanha
    { title: @passo['titulo'], inbox_id: @caixa.id, template_params: @template_params, variable_bindings: variaveis,
      message: ::Autonomia::Automacao::PassoDeCampanha.texto_do_modelo(@caixa, @template_params), scheduled_at: Time.current.iso8601 }
  end

  # O texto fixo de cada variável do corpo (o modelo_pronto já o montou), no formato do Público.
  def variaveis
    @template_params.dig('processed_params', 'body').to_h.transform_values { |texto| { 'source' => 'fixed', 'value' => texto } }
  end

  # "<nome da campanha> · <data>", com a data no fuso e no idioma da conta (o job roda no idioma padrão).
  def nome_do_publico
    data = Time.current.in_time_zone(::Autonomia::Automacao::Tempo.fuso(@conta)).to_date
    formato = I18n.t('autonomia.automacao.data_do_publico', locale: @conta.locale.presence || I18n.default_locale)
    "#{@passo['titulo']} · #{data.strftime(formato)}"
  end

  def quem_ligou = @execucao.automacao.ligada_por

  def publico_id(campanha) = CampaignAudienceLink.for_campaign(campanha)&.campaign_import_id

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: { 'fora' => @contatos.fora })
end
