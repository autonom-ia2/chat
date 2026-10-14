require 'rails_helper'

# #1548: o critério padrão da etapa sai do modelo do funil e da posição da etapa nele, não do nome. Assim o pacote de
# textos por tipo de conta (#1545) pode renomear as etapas sem deixá-las sem critério.
RSpec.describe 'CRM critério padrão por modelo e posição (#1548)', type: :request do
  around do |example|
    previous_crm = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_ai = ENV.fetch('CRM_AI_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV['CRM_AI_ENABLED'] = 'true'
    example.run
  ensure
    previous_crm.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_crm
    previous_ai.nil? ? ENV.delete('CRM_AI_ENABLED') : ENV['CRM_AI_ENABLED'] = previous_ai
  end

  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  def serve_pipeline(template)
    pipeline, = create_crm_pipeline(account: account, user: user, name: 'Sinistros')
    pipeline.update!(counts_as_sale: false, metadata: pipeline.metadata.merge('template' => template))
    pipeline
  end

  def create_stage(pipeline, stage)
    post "#{base}/pipelines/#{pipeline.id}/stages", params: { stage: stage }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:created)
    account.crm_pipeline_stages.find(response.parsed_body.dig('payload', 'id'))
  end

  it 'a etapa do modelo ganha o critério da posição, mesmo com outro nome' do
    stage = create_stage(serve_pipeline('COBRANCA'), { name: 'Boleto em atraso', template_position: 2 })

    expect(stage.metadata['ai_criteria']).to eq(I18n.t('crm.stage_criteria.cobranca.e2', locale: I18n.default_locale))
    expect(stage.metadata['ai_criteria']).to be_present
  end

  it 'etapa avulsa, sem posição, continua achando pelo nome' do
    stage = create_stage(serve_pipeline('COBRANCA'), { name: 'Pago' })

    expect(stage.metadata['ai_criteria']).to include('comprovante')
  end

  it 'funil de Vender não recebe frase de Atender pela posição' do
    pipeline, = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: pipeline.metadata.merge('template' => 'COBRANCA'))

    stage = create_stage(pipeline, { name: 'Etapa nova', template_position: 1 })

    expect(stage.metadata).not_to have_key('ai_criteria')
  end

  it 'não troca o critério que a pessoa escreveu' do
    stage = create_stage(serve_pipeline('COBRANCA'), { name: 'Atrasado', template_position: 2, metadata: { ai_criteria: 'Meu texto' } })

    expect(stage.metadata['ai_criteria']).to eq('Meu texto')
  end

  it 'a tela de criar recebe a frase pelo modelo e pela posição, e pelo nome quando a etapa é da pessoa' do
    get "#{base}/stage_criteria/defaults",
        params: { names: ['Sinistro aberto', 'Pago', 'Minha etapa'], atender: true, template: 'COBRANCA', positions: %w[1 0 0] },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    criterios = response.parsed_body['payload'].pluck('criteria')
    expect(criterios[0]).to eq(I18n.t('crm.stage_criteria.cobranca.e1', locale: I18n.default_locale))
    expect(criterios[0]).to be_present
    expect(criterios[1]).to include('comprovante')
    expect(criterios[2]).to eq('')
  end
end
