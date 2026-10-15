require 'rails_helper'

# #1548 (passo 2): o funil de Atender criado pelo modelo segue a variante do tipo de conta (F1 da Segmentação, #1550).
# Saúde e benefícios: a E3 do Atendimento ("Esperando a operadora") nasce andamento e não pausa o prazo. Sem o
# interruptor AUTONOMIA_PACOTES_ENABLED, ou em outro tipo, tudo como hoje. Funil que já existe não muda.
RSpec.describe 'CRM variante do modelo por tipo de conta (#1548)', type: :request do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:account) { create(:account, internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil }) }
  let(:perfil) { 'saude_beneficios' }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
  end

  def serve_pipeline(template = 'ATENDIMENTO')
    pipeline, = create_crm_pipeline(account: account, user: user, name: 'Atendimentos')
    pipeline.update!(counts_as_sale: false, metadata: pipeline.metadata.merge('template' => template))
    pipeline
  end

  # A tela manda a categoria da lista que conhece; o servidor aplica a variante da conta por cima.
  def create_stage(pipeline, stage)
    post "#{base}/pipelines/#{pipeline.id}/stages", params: { stage: stage }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:created)
    account.crm_pipeline_stages.find(response.parsed_body.dig('payload', 'id'))
  end

  def e3(pipeline)
    create_stage(pipeline, { name: 'Esperando a operadora', category: 'espera', template_position: 3 })
  end

  it 'saúde com o interruptor ligado: a E3 do Atendimento nasce andamento' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(e3(serve_pipeline).metadata['category']).to eq('andamento')
    end
  end

  it 'saúde sem o interruptor: a E3 continua espera' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      expect(e3(serve_pipeline).metadata['category']).to eq('espera')
    end
  end

  context 'with a broker account (corretora)' do
    let(:perfil) { 'corretora' }

    it 'a E3 continua espera' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        expect(e3(serve_pipeline).metadata['category']).to eq('espera')
      end
    end
  end

  it 'saúde: outros modelos de Atender e etapas avulsas ficam como hoje' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      pos_venda = e3(serve_pipeline('POS_VENDA'))
      avulsa = create_stage(serve_pipeline, { name: 'Minha etapa', category: 'espera' })

      expect([pos_venda, avulsa].map { |stage| stage.metadata['category'] }).to eq(%w[espera espera])
    end
  end

  it 'funil de Vender com modelo de Atender gravado não recebe a variante' do
    pipeline = serve_pipeline
    pipeline.update!(counts_as_sale: true)

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(e3(pipeline).metadata['category']).to eq('espera')
    end
  end

  it 'funil que já existe não muda quando o interruptor liga' do
    pipeline = serve_pipeline
    stage = with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) { e3(pipeline) }

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      patch "#{base}/stages/#{stage.id}", params: { stage: { name: 'Outro nome', template_position: 3 } }, headers: auth_headers(user),
                                          as: :json
    end

    expect(response).to have_http_status(:ok)
    expect(stage.reload.metadata['category']).to eq('espera')
  end
end
