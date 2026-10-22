require 'rails_helper'

# #2067: a conversa diz ao painel de qual agente de IA ela veio (meta.veio_da_ia), com a flag da conta: na leitura, nas
# listas (conversas, contato e empresa) e no evento ao vivo da troca de dono, só para a equipe. Nunca vai ao contato
# (widget) nem ao webhook.
RSpec.describe 'Veio da IA no payload da conversa', type: :request do
  context 'with an external bot' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:ana) { create(:user, account: account, role: :administrator, name: 'Ana') }
    let(:bot) { create(:agent_bot, account: account, name: 'Lia') }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload }
    let(:esperado) { { 'tipo' => 'robo', 'id' => bot.id, 'name' => 'Lia' } }

    before do
      allow(Crm::Config).to receive(:enabled?).and_return(true)
      account.enable_features!('ficar_com_a_conversa_ao_enviar')
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
      create(:inbox_member, inbox: inbox, user: ana)
      conversation.update!(ai_assignee: bot)
      Current.user = ana
      conversation.update!(assignee: ana) # a pessoa assume: o registro grava Lia → Ana
      Current.reset
    end

    def get_json(url)
      get url, headers: ana.create_new_auth_token, as: :json
      response.parsed_body
    end

    it 'na conversa lida sozinha e nas listas de conversas e do contato', :aggregate_failures do
      show = get_json(api_v1_account_conversation_url(account_id: account.id, id: conversation.display_id))
      expect(show.dig('meta', 'veio_da_ia')).to eq(esperado)

      lista = get_json(api_v1_account_conversations_url(account_id: account.id, assignee_type: 'all'))
      expect(lista.dig('data', 'payload').first.dig('meta', 'veio_da_ia')).to eq(esperado)

      do_contato = get_json(api_v1_account_contact_conversations_url(account_id: account.id, contact_id: contact.id))
      expect(do_contato['payload'].first.dig('meta', 'veio_da_ia')).to eq(esperado)
    end

    it 'na lista da empresa', :aggregate_failures do
      skip 'sem o Enterprise' unless ChatwootApp.enterprise?

      account.enable_features!('companies')
      empresa = create(:company, account: account)
      contact.update!(company: empresa)

      da_empresa = get_json("/api/v1/accounts/#{account.id}/companies/#{empresa.id}/conversations")
      expect(da_empresa['payload'].first.dig('meta', 'veio_da_ia')).to eq(esperado)
    end

    # Pega a consulta a cada troca de conversa: marcar lida/não lida não calcula de onde a conversa veio.
    it 'marcar como lida e não lida: não calcula nem leva a chave', :aggregate_failures do
      expect(Crm::Passagens::VeioDaIa).not_to receive(:de)
      expect(Crm::Passagens::VeioDaIa).not_to receive(:da_lista)

      %w[update_last_seen unread].each do |acao|
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/#{acao}",
             headers: ana.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']).not_to have_key('veio_da_ia')
      end
    end

    # Pega a tela nova com a flag desligada: o payload é o de antes (sem a chave).
    it 'flag desligada: a chave nem existe', :aggregate_failures do
      account.disable_features!('ficar_com_a_conversa_ao_enviar')

      show = get_json(api_v1_account_conversation_url(account_id: account.id, id: conversation.display_id))
      expect(show['meta']).not_to have_key('veio_da_ia')
      lista = get_json(api_v1_account_conversations_url(account_id: account.id, assignee_type: 'all'))
      expect(lista.dig('data', 'payload').first['meta']).not_to have_key('veio_da_ia')
    end

    # Pega o vazamento para o widget do contato e o custo em todo evento ao vivo.
    describe 'eventos ao vivo' do
      let(:listener) { ActionCableListener.instance }
      let(:evento) { Events::Base.new('evento', Time.zone.now, conversation: conversation.reload) }

      let(:enviados) { {} }

      before do
        allow(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, nome, dados|
          enviados[nome] = dados
        end
      end

      def broadcast_de(nome)
        enviados.fetch(nome)
      end

      it 'a troca de dono (só para a equipe) leva de onde a conversa veio' do
        listener.assignee_changed(evento)

        expect(broadcast_de('assignee.changed').dig(:meta, :veio_da_ia)).to eq(tipo: 'robo', id: bot.id, name: 'Lia')
      end

      it 'o evento que vai também ao contato não calcula nem leva', :aggregate_failures do
        expect(Crm::Passagens::VeioDaIa).not_to receive(:de)

        listener.conversation_updated(evento)

        expect(broadcast_de('conversation.updated')[:meta]).not_to have_key(:veio_da_ia)
        expect(conversation.webhook_data[:meta]).not_to have_key(:veio_da_ia)
      end

      it 'flag desligada: a troca de dono vai como antes' do
        account.disable_features!('ficar_com_a_conversa_ao_enviar')

        listener.assignee_changed(Events::Base.new('evento', Time.zone.now, conversation: conversation.reload))

        expect(broadcast_de('assignee.changed')[:meta]).not_to have_key(:veio_da_ia)
      end
    end

    it 'Devolver para robô de outro sistema: a atribuição de robô tira a pessoa e a linha some', :aggregate_failures do
      post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
           params: { assignee_id: bot.id, assignee_type: 'AgentBot' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
      expect(Crm::Passagens::VeioDaIa.de(conversation)).to be_nil
    end
  end

  # Devolver para o agente nosso é a passagem completa (Autonomia::Agents::PassarParaIa, `por: :pessoa`): evento depois
  # do commit (o ReenfileirarTurno e o AoReceberPassagem escutam), registro da passagem e recusas com motivo.
  context 'with one of our AI agents' do
    include_context 'with crm responsible agent'

    let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }

    before do
      account.enable_features!('ficar_com_a_conversa_ao_enviar')
      create(:inbox_member, inbox: inbox, user: ana)
      Current.user = ana
      conversation.update!(assignee: ana) # Porta → Ana
      Current.reset
    end

    def devolver(id)
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/passar_para",
           params: { destino: { tipo: 'ia', id: id } }, headers: ana.create_new_auth_token, as: :json
    end

    it 'a conversa diz que veio do agente e volta para ele pelo "Passar para", com o evento da troca', :aggregate_failures do
      veio = Crm::Passagens::VeioDaIa.de(conversation.reload)
      expect(veio).to eq(tipo: 'ia', id: agente_da_porta.id, name: 'Porta')

      eventos = []
      assinatura = ActiveSupport::Notifications.subscribe(Crm::Ai::ResponsibleAgentSync::EVENTO_TROCA) do |*, payload|
        eventos << payload
      end
      devolver(veio[:id])
      ActiveSupport::Notifications.unsubscribe(assinatura)

      expect(response).to have_http_status(:success)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
      expect(eventos.map { |evento| evento[:por] }).to eq([:pessoa])
      expect(Crm::Passagens::VeioDaIa.de(conversation)).to be_nil
    end

    it 'o agente parou depois: a devolução recusa com o motivo e a conversa fica com a pessoa', :aggregate_failures do
      agente_da_porta.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      devolver(agente_da_porta.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['codigo']).to eq('nao_atende_cliente')
      expect(conversation.reload.assignee_id).to eq(ana.id)
    end
  end
end
