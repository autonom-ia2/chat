require 'rails_helper'

# "Fechar com sucesso aqui conta como venda" e os nomes dos desfechos (#1144).
RSpec.describe 'CRM pipeline outcome API', type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:pipeline) do
    account.crm_pipelines.create!(name: 'Sinistro', created_by: user, status: :active,
                                  metadata: { 'ai' => { 'tone' => 'formal' },
                                              'meta_sync' => { 'enabled' => true, 'events' => { 'won' => true } } })
  end

  def patch_pipeline(attrs)
    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
          params: { pipeline: attrs }, headers: auth_headers(user), as: :json
  end

  it 'turns the funnel into a non-sale one, names its outcomes and stops the Meta sync' do
    patch_pipeline(counts_as_sale: false, outcome_labels: { success: '  Sinistro pago  ', failure: '' })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'counts_as_sale')).to be(false)
    metadata = pipeline.reload.metadata
    expect(pipeline.counts_as_sale).to be(false)
    expect(metadata['outcome_labels']).to eq('success' => 'Sinistro pago')
    expect(metadata.dig('ai', 'tone')).to eq('formal')
    expect(metadata.dig('meta_sync', 'enabled')).to be(false)
  end

  it 'does not let the Meta sync be turned back on while the funnel is not a sale' do
    pipeline.update!(counts_as_sale: false)

    patch_pipeline(meta_sync: { enabled: true, events: { won: true } })

    expect(response).to have_http_status(:ok)
    expect(pipeline.reload.metadata.dig('meta_sync', 'enabled')).to be(false)
  end

  it 'drops the custom names when both are blank and caps their size' do
    patch_pipeline(outcome_labels: { success: 'x' * 80, failure: 'Desistiu' })
    expect(pipeline.reload.metadata['outcome_labels']).to eq('success' => 'x' * 30, 'failure' => 'Desistiu')

    patch_pipeline(outcome_labels: { success: '', failure: ' ' })
    expect(pipeline.reload.metadata).not_to have_key('outcome_labels')
  end

  it 'closes a card of a non-sale funnel as resolved through the close endpoint' do
    pipeline.update!(counts_as_sale: false)
    stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Aberto', position: 0)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Sinistro 42')

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/close", params: { result: 'won' }, headers: auth_headers(user), as: :json

    expect(response).to have_http_status(:ok)
    expect(card.reload).to be_resolved
  end

  # #1580: outcome_labels fora de { success:, failure: } em texto é recusado na entrada, pelos dois caminhos.
  describe 'outcome_labels fora do formato' do
    let(:mensagem) { 'Outcome names must be an object with success and/or failure as text.' }

    before { pipeline.update!(metadata: pipeline.metadata.merge('outcome_labels' => { 'success' => 'Contratado' })) }

    def expect_recusa
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(mensagem)
      expect(pipeline.reload.metadata['outcome_labels']).to eq('success' => 'Contratado')
    end

    it 'recusa texto solto' do
      patch_pipeline(outcome_labels: 'Contratado')
      expect_recusa

      patch_pipeline(metadata: pipeline.metadata.merge('outcome_labels' => 'Contratado'))
      expect_recusa
    end

    it 'recusa lista' do
      patch_pipeline(outcome_labels: %w[Contratado Desistiu])
      expect_recusa

      patch_pipeline(metadata: pipeline.metadata.merge('outcome_labels' => %w[Contratado Desistiu]))
      expect_recusa
    end

    it 'recusa chave desconhecida ou valor que não é texto' do
      patch_pipeline(outcome_labels: { success: 'Contratado', outro: 'x' })
      expect_recusa

      patch_pipeline(outcome_labels: { success: { nome: 'Contratado' } })
      expect_recusa

      patch_pipeline(metadata: pipeline.metadata.merge('outcome_labels' => { 'success' => 42 }))
      expect_recusa
    end

    it 'recusa ao criar, sem criar o funil' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/pipelines",
             params: { pipeline: { name: 'Novo', outcome_labels: 'Contratado' } }, headers: auth_headers(user), as: :json
      end.not_to change(Crm::Pipeline, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(mensagem)
    end

    it 'aceita o formato válido pelos dois caminhos, só success ou os dois' do
      patch_pipeline(outcome_labels: { failure: 'Desistiu' })
      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.metadata['outcome_labels']).to eq('failure' => 'Desistiu')

      patch_pipeline(metadata: pipeline.metadata.merge('outcome_labels' => { 'success' => 'Apólice', 'failure' => 'Não fechou' }))
      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.metadata['outcome_labels']).to eq('success' => 'Apólice', 'failure' => 'Não fechou')
    end

    it 'não trava o funil que já tinha o dado fora do formato quando outro campo muda' do
      pipeline.update_column(:metadata, pipeline.metadata.merge('outcome_labels' => 'antigo')) # rubocop:disable Rails/SkipsModelValidations

      patch_pipeline(name: 'Sinistro 2')

      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.name).to eq('Sinistro 2')
    end
  end
end
