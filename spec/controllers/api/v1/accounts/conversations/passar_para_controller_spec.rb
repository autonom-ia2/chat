require 'rails_helper'

# #1593 — "Passar para…" na conversa, com o serviço real dos Agentes (Autonomia::Agents::PassarParaIa) e o registro de
# passagens real (Crm::Passagens, com o com_motivo e o listener do #1606). A área do cenário é o agente de IA que recebe.
# Cada cenário diz que falha pega.
RSpec.describe 'Conversation Passar para API', type: :request do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Lima') }
  let(:fora) { create(:user, account: account, role: :agent, name: 'Fora da Caixa') }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/passar_para" }
  let(:servico) { Autonomia::Agents::PassarParaIa }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    create(:inbox_member, inbox: inbox, user: bruno)
    conversation.update!(assignee: ana, ai_assignee: nil)
    allow(servico).to receive(:call).and_call_original
  end

  def area_com_a_conversa!
    conversation.update!(assignee: nil, ai_assignee: espelho_area)
  end

  def passagem!(origem, destino)
    Crm::Passagens.registrar!(conversation: conversation, de: origem, para: destino, pedida_por: origem, motivo: 'passar_para')
  end

  def passar(destino, quem: ana)
    post url, params: { destino: destino }, headers: quem.create_new_auth_token, as: :json
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
      expect(response.parsed_body).to include('fase2' => true, 'com_ia' => nil, 'origem' => nil)
      expect(response.parsed_body['agentes']).to include({ 'id' => area.id, 'name' => 'Área Suporte', 'com_a_conversa' => false })
    end

    # Pega: o selo "Com Lia · passada por Ana" e o "Devolver para Ana" precisam da origem do registro do CRM.
    it 'com a área na conversa: selo e origem vindos do registro de passagens', :aggregate_failures do
      area_com_a_conversa!
      passagem!(ana, area)

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body['com_ia']).to eq('id' => area.id, 'name' => 'Área Suporte', 'bot_id' => espelho_area.id)
      expect(response.parsed_body['origem']).to include('tipo' => 'pessoa', 'id' => ana.id, 'name' => 'Ana Souza', 'pode_receber' => true)
      expect(response.parsed_body['agentes'].find { |agente| agente['id'] == area.id }['com_a_conversa']).to be(true)
    end

    # Pega: oferecer "Devolver para" quem já saiu da caixa.
    it 'origem que saiu da caixa: vem sem poder receber' do
      area_com_a_conversa!
      passagem!(fora, area)

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body.dig('origem', 'pode_receber')).to be(false)
    end

    # Pega: passagem aberta de outro agente (já trocou de mãos) virar a origem errada.
    it 'passagem aberta para outro agente: sem origem' do
      area_com_a_conversa!
      passagem!(ana, criar_agente('Maria'))

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body['origem']).to be_nil
    end

    it 'sem a Fase 2: só pessoas, sem selo e sem consultar os Agentes', :aggregate_failures do
      Autonomia::Agents::Fase2.desligar!(account)
      allow(servico).to receive(:destinos_possiveis).and_call_original

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body).to include('fase2' => false, 'agentes' => [], 'com_ia' => nil)
      expect(servico).not_to have_received(:destinos_possiveis)
    end
  end

  describe 'POST' do
    # Pega: passar para pessoa sem o motivo no registro, ou gravando a passagem em dobro (quem grava é o listener do CRM).
    it 'para pessoa: a atribuição de hoje e uma passagem só, com o motivo passar_para', :aggregate_failures do
      expect { passar({ tipo: 'pessoa', id: bruno.id }) }.to change(Crm::Passagem, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.assignee_id).to eq(bruno.id)
      expect(response.parsed_body.dig('assignee', 'id')).to eq(bruno.id)
      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect(passagem.motivo).to eq('passar_para')
      expect([passagem.para.classe, passagem.para.id]).to eq(['User', bruno.id])
    end

    it 'devolver para a origem com a área na conversa: a pessoa assume e a área sai', :aggregate_failures do
      area_com_a_conversa!

      passar({ tipo: 'pessoa', id: ana.id })

      expect(response).to have_http_status(:ok)
      expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    end

    # Pega: passar a conversa para quem não pode vê-la (fora da caixa).
    it 'pessoa fora da caixa: 422 com código, e nada muda', :aggregate_failures do
      expect { passar({ tipo: 'pessoa', id: fora.id }) }.not_to change(Crm::Passagem, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('codigo' => 'pessoa_fora_da_caixa')
      expect(conversation.reload.assignee_id).to eq(ana.id)
    end

    # Pega: o CRM gravar uma segunda passagem quando quem grava é o serviço dos Agentes.
    # Pega também origem e pedida_por trocadas: quem estava com a conversa (Ana) não é quem pediu (Bruno).
    it 'para a área: o serviço dos Agentes recebe a origem e quem pediu, e grava uma passagem só', :aggregate_failures do
      expect { passar({ tipo: 'ia', id: area.id }, quem: bruno) }.to change(Crm::Passagem, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(servico).to have_received(:call).with(conversation: conversation, agent: area, por: :pessoa, motivo: 'passar_para',
                                                   origem: ana, pedida_por: bruno, transfer_id: nil)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect([passagem.de.id, passagem.pedida_por.id, passagem.para.id]).to eq([ana.id, bruno.id, area.id])
    end

    it 'a área já está com a conversa (ja_e_o_dono): ok, sem erro e sem passagem nova', :aggregate_failures do
      area_com_a_conversa!

      expect { passar({ tipo: 'ia', id: area.id }) }.not_to change(Crm::Passagem, :count)

      expect(response).to have_http_status(:ok)
    end

    # Pega: a recusa dos Agentes virar 500 ou sumir; a tela precisa do código para explicar. Cada recusa acontece de
    # verdade no banco. `outra_conta` e `pessoa_atribuida` não chegam por aqui: agente de outra conta é destino_invalido
    # (abaixo), e a pessoa que pede sempre pode tirar a conversa de uma pessoa.
    def preparar_recusa!(codigo)
      case codigo
      when 'fase2_desligada' then Autonomia::Agents::Fase2.desligar!(account)
      when 'nao_atende_cliente'
        area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations
      when 'sem_vinculo_na_caixa' then area_sumiu!
      when 'conversa_resolvida' then conversation.update!(status: :resolved)
      end
    end

    %w[fase2_desligada nao_atende_cliente sem_vinculo_na_caixa conversa_resolvida].each do |codigo|
      it "recusa #{codigo}: 422 com o código, e nada muda", :aggregate_failures do
        preparar_recusa!(codigo)

        expect { passar({ tipo: 'ia', id: area.id }) }.not_to change(Crm::Passagem, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('codigo' => codigo)
        expect(conversation.reload.ai_assignee).to be_nil
      end
    end

    # Pega: id de agente de outra conta chegar ao serviço.
    it 'agente de outra conta: 422 destino_invalido, sem chamar o serviço', :aggregate_failures do
      outra = create(:account)
      alheio = Autonomia::Agents::Agent.create!(account: outra, name: 'Alheio', agent_type: 'custom', status: :active, enabled: true)

      passar({ tipo: 'ia', id: alheio.id })

      expect(response.parsed_body).to eq('codigo' => 'destino_invalido')
      expect(servico).not_to have_received(:call)
    end

    it 'tipo desconhecido: 422 destino_invalido' do
      passar({ tipo: 'time', id: 1 })

      expect(response.parsed_body).to eq('codigo' => 'destino_invalido')
    end
  end
end
