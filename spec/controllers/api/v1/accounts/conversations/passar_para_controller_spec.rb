require 'rails_helper'

# #1593 — "Passar para…" na conversa. O serviço dos Agentes (PassarParaIa) e o registro de passagens (Crm::Passagens,
# #1606) são dublês por contrato (PassarParaIaHelper). Cada cenário diz que falha pega.
RSpec.describe 'Conversation Passar para API', type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Lima') }
  let(:fora) { create(:user, account: account, role: :agent, name: 'Fora da Caixa') }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: ana, status: :open) }
  let(:lia) { criar_agente_ia(account, 'Lia') }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/passar_para" }
  let!(:servico) { dublar_passar_para_ia(destinos: [lia]) }
  let!(:passagens) { dublar_passagens }

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    create(:inbox_member, inbox: inbox, user: bruno)
    allow(Crm::Ai::Config).to receive(:areas_ligadas?).and_return(true)
  end

  def espelho_da_lia_com_a_conversa!
    Autonomia::Agents::AgentInbox.create!(agent: lia, inbox: inbox, account: account, agent_bot: bot)
    conversation.update!(assignee: nil, ai_assignee: bot)
  end

  it 'sem login: 401' do
    get url

    expect(response).to have_http_status(:unauthorized)
  end

  # Pega: quem não vê a conversa conseguir ler ou passá-la.
  it 'quem não está na caixa não lê nem passa' do
    get url, headers: fora.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'GET' do
    it 'lista os agentes que podem receber, sem selo enquanto uma pessoa está com a conversa', :aggregate_failures do
      get url, headers: ana.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('fase2' => true, 'com_ia' => nil, 'origem' => nil,
                                              'agentes' => [{ 'id' => lia.id, 'name' => 'Lia', 'com_a_conversa' => false }])
    end

    # Pega: o selo "Com Lia · passada por Ana" e o "Devolver para Ana" precisam da origem do registro do CRM.
    it 'com a Lia na conversa: selo e origem vindos do registro de passagens', :aggregate_failures do
      espelho_da_lia_com_a_conversa!
      aberta = double('passagem', de: ponta(ana), para: ponta(lia))
      allow(passagens).to receive(:ultima_aberta).and_return(aberta)

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body['com_ia']).to eq('id' => lia.id, 'name' => 'Lia')
      expect(response.parsed_body['origem']).to include('tipo' => 'pessoa', 'id' => ana.id, 'name' => 'Ana Souza', 'pode_receber' => true)
      expect(response.parsed_body['agentes'].first['com_a_conversa']).to be(true)
    end

    # Pega: oferecer "Devolver para" quem já saiu da caixa.
    it 'origem que saiu da caixa: vem sem poder receber' do
      espelho_da_lia_com_a_conversa!
      allow(passagens).to receive(:ultima_aberta).and_return(double('passagem', de: ponta(fora), para: ponta(lia)))

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body.dig('origem', 'pode_receber')).to be(false)
    end

    # Pega: passagem aberta de outro agente (já trocou de mãos) virar a origem errada.
    it 'passagem aberta para outro agente: sem origem' do
      espelho_da_lia_com_a_conversa!
      outro = criar_agente_ia(account, 'Maria')
      allow(passagens).to receive(:ultima_aberta).and_return(double('passagem', de: ponta(ana), para: ponta(outro)))

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body['origem']).to be_nil
    end

    it 'sem a Fase 2: só pessoas, sem selo e sem chamar os Agentes', :aggregate_failures do
      allow(Crm::Ai::Config).to receive(:areas_ligadas?).and_return(false)

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body).to include('fase2' => false, 'agentes' => [], 'com_ia' => nil)
      expect(servico).not_to have_received(:destinos_possiveis)
    end
  end

  describe 'POST' do
    # Pega: passar para pessoa sem o motivo no registro, ou gravando a passagem em dobro (o escritor de atribuição a
    # pessoa é o listener do CRM; aqui só o motivo).
    it 'para pessoa: a atribuição de hoje, com o motivo marcado e sem gravar passagem própria', :aggregate_failures do
      post url, params: { destino: { tipo: 'pessoa', id: bruno.id } }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.assignee_id).to eq(bruno.id)
      expect(response.parsed_body.dig('assignee', 'id')).to eq(bruno.id)
      expect(passagens).to have_received(:com_motivo).with('passar_para')
      expect(passagens).not_to have_received(:registrar!)
    end

    it 'devolver para a origem com a Lia na conversa: a pessoa assume e a Lia sai', :aggregate_failures do
      espelho_da_lia_com_a_conversa!

      post url, params: { destino: { tipo: 'pessoa', id: ana.id } }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    end

    # Pega: passar a conversa para quem não pode vê-la (fora da caixa).
    it 'pessoa fora da caixa: 422 com código, e nada muda', :aggregate_failures do
      post url, params: { destino: { tipo: 'pessoa', id: fora.id } }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('codigo' => 'pessoa_fora_da_caixa')
      expect(conversation.reload.assignee_id).to eq(ana.id)
      expect(passagens).not_to have_received(:registrar!)
    end

    # Pega: o CRM gravar uma segunda passagem quando quem grava é o serviço dos Agentes.
    it 'para a Lia: chama o serviço dos Agentes com a pessoa como origem, e não grava passagem própria', :aggregate_failures do
      post url, params: { destino: { tipo: 'ia', id: lia.id } }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(servico).to have_received(:call).with(conversation: conversation, agent: lia, por: :pessoa, motivo: 'passar_para',
                                                   origem: ana, transfer_id: nil)
      expect(passagens).not_to have_received(:registrar!)
    end

    it 'a Lia já está com a conversa (ja_e_o_dono): ok, sem erro' do
      allow(servico).to receive(:call).and_return(resultado_da_ia(:ja_e_o_dono))

      post url, params: { destino: { tipo: 'ia', id: lia.id } }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
    end

    # Pega: a recusa dos Agentes virar 500 ou sumir; a tela precisa do código para explicar.
    %i[fase2_desligada nao_atende_cliente sem_vinculo_na_caixa outra_conta conversa_resolvida].each do |codigo|
      it "recusa #{codigo}: 422 com o código" do
        allow(servico).to receive(:call).and_return(resultado_da_ia(codigo))

        post url, params: { destino: { tipo: 'ia', id: lia.id } }, headers: ana.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('codigo' => codigo.to_s)
      end
    end

    # Pega: id de agente de outra conta chegar ao serviço.
    it 'agente de outra conta: 422 destino_invalido, sem chamar o serviço', :aggregate_failures do
      alheio = criar_agente_ia(create(:account), 'Alheio')

      post url, params: { destino: { tipo: 'ia', id: alheio.id } }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('codigo' => 'destino_invalido')
      expect(servico).not_to have_received(:call)
    end

    it 'tipo desconhecido: 422 destino_invalido' do
      post url, params: { destino: { tipo: 'time', id: 1 } }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('codigo' => 'destino_invalido')
    end
  end
end
