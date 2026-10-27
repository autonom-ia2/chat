# Lead de formulário instantâneo que chega pelo webhook da Página (#2195). Contrato com o roteador do #2200: um job por
# change com field 'leadgen', `perform_later(entry['id'], change['value'], entry['time'])`; a assinatura do webhook já
# foi conferida lá.
#
# Para cada conta em que a Página está recebendo, com a flag `meta_ads_formularios` e funil escolhido para aquele
# formulário (funil ativo): busca o lead com o token da Página (leads_retrieval, tirado na hora do token do cliente) e
# cria o card (Crm::MetaAds::LeadForms::Importer, idempotente pelo leadgen_id). Falha passageira da Meta: tenta de novo.
class Webhooks::FacebookLeadgenJob < ApplicationJob
  queue_as :default
  # A Meta fora do ar depois das 5 tentativas: o lead não entra agora. O leadgen_id vai ao rastreador, e "Trazer
  # quem já preencheu" (últimos 90 dias) recupera; o Importer não duplica quem já entrou. Reconciliação sozinha: #2285.
  retry_on Crm::MetaAds::LeadForms::Unavailable, wait: :polynomially_longer, attempts: 5 do |job, _error|
    page_id, value = job.arguments
    leadgen_id = value.to_h.stringify_keys['leadgen_id']
    lost = StandardError.new("Lead do formulário não entrou: Meta fora do ar (leadgen_id=#{leadgen_id}, page_id=#{page_id})")
    ChatwootExceptionTracker.new(lost).capture_exception
  end

  FEATURE = 'meta_ads_formularios'.freeze

  def perform(page_id, value, _time = nil)
    value = value.to_h.stringify_keys
    return if value['leadgen_id'].blank? || value['form_id'].blank?

    # Uma conta com a Meta fora do ar não segura as outras: todas rodam, e o job tenta de novo no fim (o Importer não
    # duplica as que já entraram).
    unavailable = nil
    Crm::MetaAdsPage.leadgen_receiving.where(page_id: page_id.to_s).includes(:account).find_each do |page|
      import(page, value)
    rescue Crm::MetaAds::LeadForms::Unavailable => e
      unavailable = e
    end
    raise unavailable if unavailable
  end

  private

  def import(page, value)
    account = page.account
    form = destination_form(account, value['form_id'])
    connection = Crm::MetaAdsConnection.active.find_by(account_id: account.id) if form
    return unless connection&.own_token?

    client = page_client(connection, page.page_id)
    lead = client && check!(client.lead(value['leadgen_id']), connection)
    importer(account, form, client).import(lead.data) if lead
  end

  def destination_form(account, form_id)
    return unless account.feature_enabled?(FEATURE)

    form = Crm::MetaAdsLeadForm.includes(:pipeline).find_by(account_id: account.id, form_id: form_id.to_s)
    form if form&.destination? && form.pipeline.active?
  end

  def page_client(connection, page_id)
    result = Meta::AdsGraphClient.new(access_token: connection.read_token).page_access_token(page_id)
    token = check!(result, connection)&.data.to_h['access_token']
    Meta::AdsGraphClient.new(access_token: token) if token.present?
  end

  def importer(account, form, client)
    questions = client.lead_form_questions(form.form_id)
    Crm::MetaAds::LeadForms::Importer.new(
      account: account, pipeline: form.pipeline, stage: form.stage, form_name: form.form_name, page_id: form.page_id,
      questions: questions.ok ? Array(questions.data.to_h['questions']) : []
    )
  end

  # Passageira: de novo. Token recusado: a conexão passa a precisar de atenção, como nas outras leituras. Sem permissão
  # (leads_retrieval tirada): vai ao rastreador só com o código. Lead apagado: nada a fazer.
  def check!(result, connection)
    return result if result.ok
    raise Crm::MetaAds::LeadForms::Unavailable if result.transient?

    refused!(result, connection)
    nil
  end

  def refused!(result, connection)
    return connection.mark_invalid!(result.error_message) if result.token_invalid?
    return unless result.scope_error?

    error = StandardError.new("Meta recusou ler o lead do formulário (code=#{result.error_code})")
    ChatwootExceptionTracker.new(error, account: connection.account).capture_exception
  end
end
