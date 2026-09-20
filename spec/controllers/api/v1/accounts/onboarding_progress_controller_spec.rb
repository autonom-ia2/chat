require 'rails_helper'

RSpec.describe 'Onboarding progress API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/onboarding/progress" }

  describe 'GET progress' do
    it 'exige autenticação' do
      get base, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devolve a trilha inteira para o administrador' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      passos = response.parsed_body['passos']
      expect(passos.pluck('id')).to eq(
        %w[perfil chave_ia canal primeira_resposta funil equipe agente_ia campanha configuracoes]
      )
      expect(passos.pluck('status').uniq).to eq(['pendente'])
    end

    it 'mostra ao agente só os passos do trabalho dele' do
      get base, headers: agente.create_new_auth_token, as: :json

      expect(response.parsed_body['passos'].pluck('id')).to eq(%w[perfil primeira_resposta])
    end

    it 'responde rápido numa conta com volume de conversas' do
      inbox = create(:inbox, account: account)
      conversa = create(:conversation, account: account, inbox: inbox)
      create_list(:message, 50, account: account, conversation: conversa, message_type: :incoming)

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      get base, headers: admin.create_new_auth_token, as: :json
      decorrido = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000

      expect(response).to have_http_status(:success)
      expect(decorrido).to be < 300
    end
  end

  describe 'POST skip' do
    it 'pula passo pulável e grava na conta' do
      post "#{base}/equipe/skip", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('passo' => 'equipe', 'status' => 'pulado')
      expect(account.reload.custom_attributes['onboarding_passos_pulados']).to eq(['equipe'])
    end

    it 'recusa passo que não é pulável' do
      post "#{base}/chave_ia/skip", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.custom_attributes['onboarding_passos_pulados']).to be_blank
    end

    it 'recusa passo inexistente' do
      post "#{base}/inventado/skip", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST resume' do
    it 'devolve o passo pulado para pendente' do
      post "#{base}/equipe/skip", headers: admin.create_new_auth_token, as: :json
      post "#{base}/equipe/resume", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.reload.custom_attributes['onboarding_passos_pulados']).to eq([])
    end
  end
end
