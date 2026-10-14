require 'rails_helper'

# Tipo de funil Vender × Atender (#1498): o modelo do funil, a categoria das etapas, as frases padrão de Atender e a
# promessa de pagamento da Cobrança.
RSpec.describe 'CRM tipo de funil (#1498)', type: :request do
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

  describe 'modelo do funil' do
    it 'grava o modelo ao criar, sem apagar a meta nem os nomes dos desfechos' do
      post "#{base}/pipelines",
           params: { pipeline: { name: 'Cobrança', counts_as_sale: false, template: 'COBRANCA',
                                 outcome_labels: { success: 'Pago' } } },
           headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:created)
      metadata = response.parsed_body.dig('payload', 'metadata')
      expect(metadata['template']).to eq('COBRANCA')
      expect(metadata.dig('outcome_labels', 'success')).to eq('Pago')
      expect(metadata['ai']).to be_present
    end

    it 'ignora um modelo que não existe' do
      pipeline, = create_crm_pipeline(account: account, user: user)
      pipeline.update!(metadata: pipeline.metadata.merge('template' => 'VENDAS'))

      patch "#{base}/pipelines/#{pipeline.id}", params: { pipeline: { template: 'SEGUROS' } },
                                                headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.metadata['template']).to eq('VENDAS')
    end

    it 'não aceita modelo desconhecido nem quando vem dentro de metadata' do
      pipeline, = create_crm_pipeline(account: account, user: user)

      patch "#{base}/pipelines/#{pipeline.id}", params: { pipeline: { metadata: { template: 'SEGUROS' } } },
                                                headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.metadata).not_to have_key('template')
    end
  end

  describe 'categoria da etapa' do
    it 'grava só as categorias conhecidas, ao criar e ao mudar' do
      pipeline, = create_crm_pipeline(account: account, user: user)

      post "#{base}/pipelines/#{pipeline.id}/stages", params: { stage: { name: 'Prometeu pagar', category: 'espera' } },
                                                      headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:created)
      stage = account.crm_pipeline_stages.find(response.parsed_body.dig('payload', 'id'))
      expect(stage.metadata['category']).to eq('espera')

      patch "#{base}/stages/#{stage.id}", params: { stage: { name: 'Prometeu pagar', category: 'qualquer' } },
                                          headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(stage.reload.metadata).not_to have_key('category')

      patch "#{base}/stages/#{stage.id}", params: { stage: { name: 'Prometeu pagar', metadata: { category: 'qualquer' } } },
                                          headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(stage.reload.metadata).not_to have_key('category')
    end
  end

  describe 'frases padrão das etapas' do
    it 'em funil de Atender, "Em atendimento" não fala de proposta' do
      pipeline, = create_crm_pipeline(account: account, user: user, name: 'Suporte')
      pipeline.update!(counts_as_sale: false)

      post "#{base}/pipelines/#{pipeline.id}/stages", params: { stage: { name: 'Em atendimento' } },
                                                      headers: auth_headers(user), as: :json

      stage = account.crm_pipeline_stages.find(response.parsed_body.dig('payload', 'id'))
      expect(stage.metadata['ai_criteria']).to include('cuidando do pedido')
      expect(stage.metadata['ai_criteria']).not_to include('proposta')
    end

    it 'funil de Vender não ganha frase de etapa de Atender' do
      pipeline, = create_crm_pipeline(account: account, user: user)

      post "#{base}/pipelines/#{pipeline.id}/stages", params: { stage: { name: 'Pago' } },
                                                      headers: auth_headers(user), as: :json

      stage = account.crm_pipeline_stages.find(response.parsed_body.dig('payload', 'id'))
      expect(stage.metadata).not_to have_key('ai_criteria')
    end

    it 'a tela de criar recebe as frases de Atender quando pede' do
      get "#{base}/stage_criteria/defaults", params: { names: ['Em atendimento', 'A vencer'], atender: true },
                                             headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      criterios = response.parsed_body['payload'].pluck('criteria')
      expect(criterios.first).to include('cuidando do pedido')
      expect(criterios.last).to include('ainda não venceu')
    end
  end

  describe 'promessa de pagamento' do
    let(:card) do
      pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Cobrança')
      pipeline.update!(counts_as_sale: false)
      account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Mensalidade de outubro',
                                metadata: { 'ai' => { 'summary' => 'Prometeu pagar' } })
    end

    it 'grava e tira a promessa sem mexer no resto do metadata' do
      patch "#{base}/cards/#{card.id}", params: { card: { payment_promise_at: '2026-10-20' } },
                                        headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(card.reload.metadata['payment_promise_at']).to eq('2026-10-20')
      expect(card.metadata.dig('ai', 'summary')).to eq('Prometeu pagar')
      registro = card.activities.where(event_type: 'update').last.payload
      expect(registro).to eq('payment_promise_at' => '2026-10-20')

      patch "#{base}/cards/#{card.id}", params: { card: { payment_promise_at: nil } },
                                        headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(card.reload.metadata).not_to have_key('payment_promise_at')
    end

    it 'recusa uma data que não existe ou fora do formato AAAA-MM-DD' do
      %w[2026-02-31 20261020 2026-10-20T10:00].each do |valor|
        patch "#{base}/cards/#{card.id}", params: { card: { payment_promise_at: valor } },
                                          headers: auth_headers(user), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(card.reload.metadata).not_to have_key('payment_promise_at')
    end
  end
end
