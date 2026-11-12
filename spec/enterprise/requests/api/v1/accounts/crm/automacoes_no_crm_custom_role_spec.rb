require 'rails_helper'

# #2499 F6.3/F6.5 com função personalizada (parecer de Funções): ver as automações do card pede `automation_view` e ver
# o card (crm_view); parar só no card pede `automation_manage` e mexer no card (crm_manage_cards); ver as da etapa pede
# `automation_view` e a chave de funis (crm_manage_pipelines ou crm_admin).
RSpec.describe 'CRM automações no card e na etapa com função personalizada', :automacao_motor, type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente_e_vinculo) { create_crm_agent(account: account) }
  let(:agente) { agente_e_vinculo.first }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:etapa) { funil_e_etapa.last }
  let(:card) { account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: etapa, owner: agente, title: 'Pedido') }
  let(:definicao) do
    automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => etapa.id })
  end
  let(:execucao) do
    Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                           chave_gatilho: 'card.entrou_na_etapa', estado: 'esperando', cursor: 'p1',
                                           due_at: 1.day.from_now)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    # A execução nasce depois dos gatilhos de card ligados: a versão com gatilho de etapa não salva sem eles.
    execucao
  end

  def com_funcao(*chaves)
    agente_e_vinculo.last.update!(custom_role: create(:custom_role, account: account, permissions: chaves))
    agente.create_new_auth_token
  end

  describe 'ver o que roda no card' do
    let(:caminho) { "#{base}/cards/#{card.id}/automacoes" }

    it 'com automation_view e crm_view, vê', :aggregate_failures do
      get caminho, headers: com_funcao('automation_view', 'crm_view'), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['automacoes'].pluck('id')).to eq([execucao.id])
    end

    it 'sem automation_view, não vê' do
      get caminho, headers: com_funcao('crm_view', 'crm_manage_cards'), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'sem ver o card (crm_view), não vê' do
      get caminho, headers: com_funcao('automation_view', 'automation_manage'), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'parar só no card' do
    let(:caminho) { "#{base}/cards/#{card.id}/automacoes/#{definicao.id}/parar" }

    it 'com automation_manage e crm_manage_cards, para', :aggregate_failures do
      post caminho, headers: com_funcao('automation_manage', 'crm_view', 'crm_manage_cards'), as: :json

      expect(response).to have_http_status(:ok)
      expect(execucao.reload.estado).to eq('parada')
    end

    it 'quem só vê automações não para', :aggregate_failures do
      post caminho, headers: com_funcao('automation_view', 'crm_view', 'crm_manage_cards'), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'quem não mexe no card não para', :aggregate_failures do
      post caminho, headers: com_funcao('automation_manage', 'crm_view'), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(execucao.reload.estado).to eq('esperando')
    end
  end

  describe 'ver as da etapa' do
    let(:caminho) { "#{base}/stages/#{etapa.id}/automacoes" }

    it 'com automation_view e crm_manage_pipelines, vê' do
      get caminho, headers: com_funcao('automation_view', 'crm_manage_pipelines'), as: :json

      expect(response.parsed_body['automacoes'].pluck('id')).to eq([definicao.id])
    end

    it 'crm_admin vale pela chave de funis' do
      get caminho, headers: com_funcao('automation_view', 'crm_admin'), as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'sem a chave de funis, não vê' do
      get caminho, headers: com_funcao('automation_view', 'crm_view'), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'sem automation_view, não vê' do
      get caminho, headers: com_funcao('crm_manage_pipelines'), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
