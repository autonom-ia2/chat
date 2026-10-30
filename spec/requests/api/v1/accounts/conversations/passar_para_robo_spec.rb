require 'rails_helper'

# #1593 — o robô de outro sistema (n8n) passa a conversa para um agente de IA da caixa pelo "Passar para…", com o
# token do robô (o mesmo que o n8n usa em produção, nunca token de pessoa). É uma ação explícita do sistema externo:
# nenhum agente nosso decide nada aqui (#2154). Serviço dos Agentes (PassarParaIa) e registro de passagens reais.
# Cada cenário diz que falha pega.
RSpec.describe 'Passar para… pelo robô de outro sistema', type: :request do
  include_context 'with crm responsible agent'

  let(:caixa_n8n) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:n8n) { create(:agent_bot, account: account, name: 'Robô n8n') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa_n8n, contact: contact, status: :open).reload }
  let(:espelho_na_caixa_n8n) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: caixa_n8n).agent_bot }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/passar_para" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    Autonomia::Agents::AgenteIaPorCaixa.ligar!(account)
    create(:agent_bot_inbox, inbox: caixa_n8n, agent_bot: n8n)
    create(:inbox_member, inbox: caixa_n8n, user: ana)
    espelho_na_caixa_n8n
    conversa.update!(assignee: nil, ai_assignee: n8n)
  end

  def token(robo = n8n)
    { api_access_token: robo.access_token.token }
  end

  def passar(destino, robo: n8n)
    post url, params: { destino: destino }, headers: token(robo), as: :json
  end

  describe 'POST' do
    # Pega: o robô levar 401 "not authorized for bots" (o que acontece hoje) ou a área não virar a dona.
    it 'robô da caixa passa para a área: ela assume e a passagem fica pedida pelo agente externo', :aggregate_failures do
      expect { passar({ tipo: 'ia', id: area.id }) }.to change(Crm::Passagem, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(conversa.reload).to have_attributes(ai_assignee: espelho_na_caixa_n8n, assignee_id: nil, status: 'open')
      expect(response.parsed_body['com_ia']).to include('id' => area.id)
      passagem = Crm::Passagens.ultima_aberta(conversa)
      expect([passagem.de.classe, passagem.de.id]).to eq(['AgentBot', n8n.id])
      expect([passagem.para.classe, passagem.para.id]).to eq(['Autonomia::Agents::Agent', area.id])
      expect([passagem.pedida_por_type, passagem.pedida_por_id]).to eq(['AgentBot', n8n.id])
    end

    # Pega: o pedido do robô passar por cima da pessoa que está atendendo (pessoa no nome vence).
    it 'com uma pessoa no nome: recusa pessoa_atribuida e a conversa fica com ela', :aggregate_failures do
      conversa.update!(assignee: ana)

      expect { passar({ tipo: 'ia', id: area.id }) }.not_to change(Crm::Passagem, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('codigo' => 'pessoa_atribuida')
      expect(conversa.reload.assignee_id).to eq(ana.id)
    end

    # Pega: o robô usar esta rota para escolher uma pessoa (para isso ele já tem o handoff, que respeita a Atribuição).
    it 'robô pedindo pessoa: recusa destino_invalido, sem atribuir', :aggregate_failures do
      passar({ tipo: 'pessoa', id: ana.id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('codigo' => 'destino_invalido')
      expect(conversa.reload.assignee_id).to be_nil
    end

    # Pega: o robô de uma caixa mexer na conversa de outra caixa da mesma conta.
    it 'robô de outra caixa: 401, nada muda', :aggregate_failures do
      outro = create(:agent_bot, account: account, name: 'Outro n8n')
      create(:agent_bot_inbox, inbox: create(:inbox, account: account), agent_bot: outro)

      expect { passar({ tipo: 'ia', id: area.id }, robo: outro) }.not_to change(Crm::Passagem, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(conversa.reload.ai_assignee).to eq(n8n)
    end

    # Pega: o robô desligado na caixa (o admin parou o n8n ali) seguir passando conversas.
    it 'robô desligado na caixa: 401' do
      caixa_n8n.agent_bot_inbox.update!(status: :inactive)

      passar({ tipo: 'ia', id: area.id })

      expect(response).to have_http_status(:unauthorized)
    end

    # Pega: um agente NOSSO disparar a passagem pelo token do espelho dele (regra máxima, #2154: agente nunca passa).
    it 'espelho de agente nosso, mesmo ligado à caixa: 401', :aggregate_failures do
      espelho_da_porta = vinculo_da_porta.agent_bot
      conversation.update!(ai_assignee: espelho_da_porta)
      url_da_porta = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/passar_para"

      post url_da_porta, params: { destino: { tipo: 'ia', id: area.id } }, headers: token(espelho_da_porta), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(conversation.reload.ai_assignee).to eq(espelho_da_porta)
    end

    # Pega: o robô de outra conta chegar à conversa.
    it 'robô de outra conta: 401' do
      de_fora = create(:agent_bot, account: create(:account), name: 'Robô de fora')

      passar({ tipo: 'ia', id: area.id }, robo: de_fora)

      expect(response).to have_http_status(:unauthorized)
    end

    # Pega: agente parado recebendo conversa porque quem pediu foi um robô.
    it 'agente parado: recusa nao_atende_cliente', :aggregate_failures do
      area.update!(status: :paused)

      passar({ tipo: 'ia', id: area.id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('codigo' => 'nao_atende_cliente')
      expect(conversa.reload.ai_assignee).to eq(n8n)
    end

    # Pega: o robô reabrir uma conversa encerrada mandando-a para a IA.
    it 'conversa resolvida: recusa conversa_resolvida' do
      conversa.update!(status: :resolved)

      passar({ tipo: 'ia', id: area.id })

      expect(response.parsed_body).to eq('codigo' => 'conversa_resolvida')
    end

    # Pega: o pedido repetido do n8n (retentativa) gravar passagem de novo.
    it 'a área já é a dona: 200 sem passagem nova' do
      passar({ tipo: 'ia', id: area.id })

      expect { passar({ tipo: 'ia', id: area.id }) }.not_to change(Crm::Passagem, :count)
      expect(response).to have_http_status(:ok)
    end

    # Pega: a rota responder fora do piloto (sem a Fase 2 dos Agentes).
    it 'sem a Fase 2: 404' do
      Autonomia::Agents::Fase2.desligar!(account)

      passar({ tipo: 'ia', id: area.id })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET' do
    # Pega: o n8n não ter como saber o id do agente de IA para quem passa.
    it 'o robô da caixa lê os agentes que podem receber', :aggregate_failures do
      get url, headers: token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['agentes']).to include(include('id' => area.id, 'name' => 'Área Suporte'))
    end
  end

  # Ponta a ponta n8n → área: o que o n8n vê depois (o filtro dele, FiltraSomenteNaoAtribuido, cala quando o dono é
  # outro robô) e o que a área recebe como dado (quem passou, como "agente externo").
  describe 'ponta a ponta' do
    it 'depois da passagem o n8n vê outro dono e a área sabe que veio do agente externo', :aggregate_failures do
      passar({ tipo: 'ia', id: area.id })

      meta = conversa.reload.push_event_data[:meta]
      expect(meta[:assignee_type]).to eq('AgentBot')
      expect(meta.dig(:assignee, :name)).not_to eq(n8n.name)
      expect(Conversation.awaiting_person.where(id: conversa.id)).to be_empty
      expect(Crm::Passagens.recentes(conversa)).to include('agente externo').and include('Robô n8n')
      expect(Autonomia::Agents::QuemResponde.agent_inbox(conversa)&.agent).to eq(area)
    end
  end
end
