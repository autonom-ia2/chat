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

    # Pega: a rota respondendo fora do piloto (o botão some, mas a API ficava aberta).
    it 'sem a Fase 2: 404, sem consultar os Agentes', :aggregate_failures do
      Autonomia::Agents::Fase2.desligar!(account)
      allow(servico).to receive(:destinos_possiveis).and_call_original

      get url, headers: ana.create_new_auth_token

      expect(response).to have_http_status(:not_found)
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
    # (abaixo), e a pessoa que pede sempre pode tirar a conversa de uma pessoa. `fase2_desligada` nem chega ao serviço: a
    # rota responde 404 (abaixo).
    def preparar_recusa!(codigo)
      case codigo
      when 'nao_atende_cliente'
        area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations
      when 'sem_vinculo_na_caixa' then area_sumiu!
      when 'conversa_resolvida' then conversation.update!(status: :resolved)
      end
    end

    %w[nao_atende_cliente sem_vinculo_na_caixa conversa_resolvida].each do |codigo|
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

    # Pega: passar a conversa (para pessoa ou agente) fora do piloto pela API.
    it 'sem a Fase 2: 404 e nada muda, nem para pessoa', :aggregate_failures do
      Autonomia::Agents::Fase2.desligar!(account)

      expect { passar({ tipo: 'pessoa', id: bruno.id }) }.not_to change(Crm::Passagem, :count)

      expect(response).to have_http_status(:not_found)
      expect(conversation.reload.assignee_id).to eq(ana.id)
      expect(servico).not_to have_received(:call)
    end

    it 'tipo desconhecido: 422 destino_invalido' do
      passar({ tipo: 'time', id: 1 })

      expect(response.parsed_body).to eq('codigo' => 'destino_invalido')
    end
  end

  # #2882 — o robô de outro sistema ligado à caixa (n8n): o "Passar para…" o oferece e devolve a conversa a ele pela
  # atribuição de robô. O espelho de agente nosso não entra (é agente, com as regras dos Agentes).
  describe 'robô da caixa' do
    let(:nina) { create(:agent_bot, account: account, name: 'Nina') }

    before do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: nina)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: espelho_area)
    end

    # Pega: o robô externo ausente da lista (o caso da conta 40), o espelho de agente aparecendo como robô, robô
    # desligado na caixa ou de outra caixa sendo oferecido, e o aviso "nenhum agente atende primeiro" com robô na caixa.
    it 'GET: lista só o robô externo ativo nesta caixa', :aggregate_failures do
      desligado = create(:agent_bot, account: account, name: 'Desligado')
      create(:agent_bot_inbox, inbox: inbox, agent_bot: desligado, status: :inactive)
      create(:agent_bot_inbox, inbox: create(:inbox, account: account), agent_bot: create(:agent_bot, account: account, name: 'Outra'))
      Autonomia::Agents::AgentInbox.where(agent_bot: porta).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body['robos']).to eq([{ 'id' => nina.id, 'name' => 'Nina', 'com_a_conversa' => false }])
      expect(response.parsed_body['sem_robo']).to be(false)
    end

    it 'GET: com o robô na conversa, marcado como quem está com ela' do
      conversation.update!(assignee: nil, ai_assignee: nina)

      get url, headers: ana.create_new_auth_token

      expect(response.parsed_body['robos']).to eq([{ 'id' => nina.id, 'name' => 'Nina', 'com_a_conversa' => true }])
    end

    # Pega: a pessoa continuar na conversa junto do robô, a conversa ficar pendente, ou a volta não ir para o registro
    # de passagens (o histórico mostraria a ida para a pessoa e nunca a volta).
    it 'POST: a pessoa sai, o robô assume, e uma passagem da pessoa para o robô', :aggregate_failures do
      conversation.update!(status: :pending)

      expect { passar({ tipo: 'robo', id: nina.id }) }.to change(Crm::Passagem, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: nina, status: 'open')
      expect(servico).not_to have_received(:call)
      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect([passagem.de.id, passagem.para.classe, passagem.para.id, passagem.motivo]).to eq([ana.id, 'AgentBot', nina.id, 'passar_para'])
    end

    # Pega: sem pessoa na conversa, a troca de dono não passa pelo listener (que só vê troca de pessoa): a volta ao robô
    # ficava sem registro, e a passagem Ana → Área seguia "não devolvida" com o robô na conversa.
    it 'POST: com o agente de IA nosso na conversa, passagem da área para o robô e a de antes devolvida', :aggregate_failures do
      area_com_a_conversa!
      anterior = passagem!(ana, area)

      expect { passar({ tipo: 'robo', id: nina.id }) }.to change(Crm::Passagem, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: nina)
      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect([passagem.de.classe, passagem.de.id, passagem.para.id, passagem.pedida_por.id])
        .to eq(['Autonomia::Agents::Agent', area.id, nina.id, ana.id])
      expect(anterior.reload.devolvida_em).to be_present
    end

    # Pega: sem pessoa na conversa, a volta de outro robô (ou de ninguém) para este ficar sem registro.
    it 'POST: de outro robô externo para este: passagem de um robô para o outro', :aggregate_failures do
      n8n = robo_ligado(inbox)
      conversation.update!(assignee: nil, ai_assignee: n8n)

      expect { passar({ tipo: 'robo', id: nina.id }) }.to change(Crm::Passagem, :count).by(1)

      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect([passagem.de.classe, passagem.de.id, passagem.para.id]).to eq(['AgentBot', n8n.id, nina.id])
    end

    it 'POST: conversa sem ninguém: passagem sem origem para o robô', :aggregate_failures do
      conversation.update!(assignee: nil, ai_assignee: nil)

      expect { passar({ tipo: 'robo', id: nina.id }) }.to change(Crm::Passagem, :count).by(1)

      expect(Crm::Passagens.ultima_aberta(conversation)).to have_attributes(de_type: nil, para_id: nina.id)
    end

    # Pega: o registro falhar depois da troca e o robô ficar com a conversa sem passagem (a troca tem de ser desfeita).
    it 'POST: o registro falha: a troca é desfeita', :aggregate_failures do
      area_com_a_conversa!
      allow(Crm::Passagens).to receive(:registrar!).and_raise(ActiveRecord::RecordInvalid)

      passar({ tipo: 'robo', id: nina.id })

      expect(response).not_to be_successful
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
    end

    # Pega: a tela dizer "pronto" quando o robô sumiu entre a lista e o clique (o AssignmentService não atribui e devolve nil).
    it 'POST: o robô sumiu antes de atribuir: 422 robo_fora_da_caixa' do
      allow(Conversations::AssignmentService).to receive(:new).and_return(instance_double(Conversations::AssignmentService, perform: nil))

      passar({ tipo: 'robo', id: nina.id })

      expect(response.parsed_body).to eq('codigo' => 'robo_fora_da_caixa')
    end

    it 'POST: o robô já está com a conversa: ok, sem passagem nova' do
      conversation.update!(assignee: nil, ai_assignee: nina)

      expect { passar({ tipo: 'robo', id: nina.id }) }.not_to change(Crm::Passagem, :count)
      expect(response).to have_http_status(:ok)
    end

    # Pega: pela API, o tipo "robo" pular a regra dos Agentes com o id do espelho, entregar a robô desligado, de outra
    # caixa ou de outra conta.
    def robo_ligado(caixa, status: :active, conta: account)
      create(:agent_bot_inbox, inbox: caixa, status: status, agent_bot: create(:agent_bot, account: conta)).agent_bot
    end

    {
      'espelho de agente nosso' => -> { espelho_area },
      'desligado na caixa' => -> { robo_ligado(inbox, status: :inactive) },
      'de outra caixa' => -> { robo_ligado(create(:inbox, account: account)) },
      'de outra conta ligado a esta caixa' => -> { robo_ligado(inbox, conta: create(:account)) }
    }.each do |caso, robo|
      it "POST: robô #{caso}: 422 robo_fora_da_caixa, e nada muda", :aggregate_failures do
        alvo = instance_exec(&robo)

        expect { passar({ tipo: 'robo', id: alvo.id }) }.not_to change(Crm::Passagem, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('codigo' => 'robo_fora_da_caixa')
        expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
      end
    end

    # Pega: devolver ao robô uma conversa resolvida a reabre (o AssignmentService reabre para robô).
    it 'POST: conversa resolvida: 422 conversa_resolvida, e ela continua resolvida', :aggregate_failures do
      conversation.update!(status: :resolved)

      passar({ tipo: 'robo', id: nina.id })

      expect(response.parsed_body).to eq('codigo' => 'conversa_resolvida')
      expect(conversation.reload.status).to eq('resolved')
    end
  end
end
