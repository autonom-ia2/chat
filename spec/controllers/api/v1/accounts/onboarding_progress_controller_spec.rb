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

    # Sem relógio (#2243): o tempo de parede varia com a carga do runner. O que mantém a resposta rápida
    # com volume é cada regra perguntar com `exists?` — o número de consultas não cresce com as mensagens,
    # nenhuma mensagem é carregada e toda consulta à tabela de mensagens para na primeira linha.
    it 'não cresce o trabalho no banco com o volume de mensagens da conta' do
      inbox = create(:inbox, account: account)
      conversa = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, conversation: conversa, message_type: :incoming)
      headers = admin.create_new_auth_token
      # A primeira requisição carrega o que é feito uma vez só (rota, autoload); fica fora da comparação.
      get base, headers: headers, as: :json

      com_uma = medir_requisicao { get base, headers: headers, as: :json }
      expect(response).to have_http_status(:success)
      create_list(:message, 49, account: account, conversation: conversa, message_type: :incoming)
      com_cinquenta = medir_requisicao { get base, headers: headers, as: :json }

      expect(response).to have_http_status(:success)
      expect(com_cinquenta[:consultas]).to eq(com_uma[:consultas])
      expect(com_cinquenta[:mensagens_carregadas]).to eq(0)
      expect(com_cinquenta[:mensagens_sem_limite]).to be_empty
    end
  end

  def medir_requisicao(&)
    medida = { consultas: 0, mensagens_carregadas: 0, mensagens_sem_limite: [] }
    contar_consulta = lambda do |*, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

      medida[:consultas] += 1
      sql = payload[:sql]
      medida[:mensagens_sem_limite] << sql if sql.include?('FROM "messages"') && sql.exclude?('LIMIT')
    end
    contar_mensagem = lambda do |*, payload|
      medida[:mensagens_carregadas] += payload[:record_count] if payload[:class_name] == 'Message'
    end
    ActiveSupport::Notifications.subscribed(contar_consulta, 'sql.active_record') do
      ActiveSupport::Notifications.subscribed(contar_mensagem, 'instantiation.active_record', &)
    end
    medida
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

  describe 'permissão' do
    it 'não deixa agente pular passo da conta' do
      post "#{base}/equipe/skip", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.custom_attributes['onboarding_passos_pulados']).to be_blank
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
