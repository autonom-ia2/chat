require 'rails_helper'

# #1593 — a regra da Atribuição levando a conversa a um agente de IA (Crm::Entrega + Crm::Entrega::ParaIa), com o
# serviço real dos Agentes (Autonomia::Agents::PassarParaIa). O espião só observa as chamadas; as corridas (o agente
# para, uma pessoa entra, o vínculo some) acontecem de verdade no banco, logo antes do serviço rodar. Cada cenário diz
# que falha pega.
RSpec.describe Crm::Entrega do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Vendas') }
  let(:servico) { Autonomia::Agents::PassarParaIa }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    allow(servico).to receive(:call).and_call_original
    create_card(pipeline: comercial)
  end

  def regra!(extra)
    comercial.stages.first.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' }.merge(extra) })
  end

  def entrega(sugestao: nil)
    described_class.new(conversation: conversation, motivo: 'ia_crm', origem: 'message', pedido: { sugestao: sugestao }).call
  end

  def parar_area!
    area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations
  end

  # Logo antes do serviço real rodar, `corrida` muda o banco (o que aconteceria entre a leitura e a passagem).
  def antes_do_servico
    allow(servico).to receive(:call).and_wrap_original do |original, **argumentos|
      yield
      original.call(**argumentos)
    end
  end

  def aviso_de_passagem_para_pessoa
    have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
  end

  describe '"A mesma pessoa" é um agente de IA' do
    before { regra!('pool_type' => 'ai_agent', 'pool_id' => area.id) }

    # Pega: a regra apontando a área entregava a uma pessoa (a IA não era destino).
    it 'passa à área pelo serviço dos Agentes, com a origem e o motivo da Atribuição, e não atribui pessoa', :aggregate_failures do
      resultado = entrega

      expect(resultado).to have_attributes(status: :com_ia, agente: area)
      expect(servico).to have_received(:call).with(hash_including(conversation: conversation, agent: area, por: :crm,
                                                                  motivo: 'atribuicao', origem: porta))
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
    end

    # Pega: agente parado (fora dos destinos) deixava a conversa sem ninguém. Agente parado = pessoa fora: equipe.
    it 'área parada (fora dos destinos): alguém da equipe recebe, sem chamar o serviço', :aggregate_failures do
      parar_area!

      expect(entrega.status).to eq(:entregue)
      expect(conversation.reload.assignee_id).to eq(ana.id)
      expect(servico).not_to have_received(:call)
    end

    # Pega: o agente parar entre a leitura e a passagem; a recusa não pode deixar a conversa parada.
    it 'a área para logo antes da passagem (o serviço recusa): entrega de novo, sem IA, para alguém da equipe', :aggregate_failures do
      antes_do_servico { parar_area! }

      expect(entrega.status).to eq(:entregue)
      expect(conversation.reload).to have_attributes(assignee_id: ana.id)
      expect(servico).to have_received(:call).once
    end

    # Pega: o serviço levantar ANTES de trocar e a entrega contar como troca feita (a conversa ficaria sem ninguém).
    it 'o serviço falha antes de trocar: alguém da equipe recebe, sem passagem para a área', :aggregate_failures do
      allow(servico).to receive(:call).and_raise(RuntimeError, 'caiu antes')

      expect(entrega.status).to eq(:entregue)
      expect(conversation.reload).to have_attributes(assignee_id: ana.id)
      expect(conversation.ai_assignee).not_to eq(espelho_area)
      expect(Crm::Passagem.where(conversation_id: conversation.id).map { |passagem| passagem.para.id }).not_to include(area.id)
    end

    # Pega: o serviço troca o dono, commita e só depois levanta (no aviso, na telemetria). Tratar isso como "não trocou"
    # passava a conversa a uma pessoa por cima: dois donos, duas passagens.
    it 'o serviço troca e falha depois do commit: fica com a área, um dono só e uma passagem só', :aggregate_failures do
      allow(servico).to receive(:call).and_wrap_original do |original, **argumentos|
        original.call(**argumentos)
        raise 'falhou depois da troca'
      end

      resultado = nil
      expect { resultado = entrega }.to change(Crm::Passagem, :count).by(1)

      expect(resultado.status).to eq(:com_ia)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      expect(Crm::Passagens.ultima_aberta(conversation).para.id).to eq(area.id)
    end

    # Pega: o laço. A área (o robô no nome é o espelho dela) pede pessoa e a regra aponta para ela mesma. O serviço
    # dos Agentes responde `passou` para quem espera pessoa, então quem barra é o CRM, antes de chamá-lo.
    it 'a própria área passa: alguém da equipe recebe, sem chamar o serviço', :aggregate_failures do
      conversation.update!(ai_assignee: espelho_area)
      esperar_pessoa!

      expect(entrega.status).to eq(:entregue)
      expect(conversation.reload.assignee_id).to eq(ana.id)
      expect(servico).not_to have_received(:call)
    end

    # Pega: uma pessoa assumiu entre a leitura e a passagem; a entrega não pode tirá-la nem dar a conversa a outra.
    it 'pessoa entra logo antes da passagem (pessoa_atribuida): fica com ela, sem cair para a equipe', :aggregate_failures do
      antes_do_servico { conversation.class.where(id: conversation.id).update_all(assignee_id: admin.id) } # rubocop:disable Rails/SkipsModelValidations
      allow(Crm::Ai::HandoffMemberSelector).to receive(:new).and_call_original

      resultado = entrega

      expect(resultado).to have_attributes(status: :nada, motivo: 'ja_tem_pessoa')
      expect(Crm::Ai::HandoffMemberSelector).not_to have_received(:new) # não tentou de novo sem IA
      expect(conversation.reload.assignee_id).to eq(admin.id)
    end

    # Pega: sem a Fase 2, a regra salva com agente não pode virar silêncio nem chamar os Agentes.
    it 'sem a Fase 2: alguém da equipe, sem chamar o serviço', :aggregate_failures do
      Autonomia::Agents::Fase2.desligar!(account)

      expect(entrega.status).to eq(:entregue)
      expect(servico).not_to have_received(:call)
    end

    # Pega: o robô passando (bot_handoff!) com a regra na área. A passagem ao agente sai depois da gravação, e não há o
    # aviso de "passou para pessoa".
    it 'na passagem do robô: grava como hoje e, depois do commit, passa à área, sem o aviso de passagem para pessoa', :aggregate_failures do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      conversation.bot_handoff!

      expect(servico).to have_received(:call).with(hash_including(conversation: conversation, agent: area, por: :crm,
                                                                  motivo: 'atribuicao', origem: porta))
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      expect(Rails.configuration.dispatcher).not_to aviso_de_passagem_para_pessoa
    end

    # Pega: o Responder e a saída da triagem chamam bot_handoff! dentro de uma trava; a passagem ao agente não pode sair
    # antes do commit dela (um rollback deixaria o agente com a conversa sem a passagem gravada).
    it 'dentro da transação de quem chama: passa à área só depois do commit', :aggregate_failures do
      chamadas = 0
      antes_do_servico { chamadas += 1 }
      chamadas_antes_do_commit = nil

      ActiveRecord::Base.transaction do
        conversation.bot_handoff!
        chamadas_antes_do_commit = chamadas
      end

      expect(chamadas_antes_do_commit).to eq(0)
      expect(chamadas).to eq(1)
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
    end

    # Pega: erro depois do commit deixava a conversa sem o aviso de passagem.
    # Pega também: sem a marca do motor, a fila não via a conversa, que ficava esperando pessoa para sempre.
    it 'na passagem do robô, erro inesperado depois do commit: o aviso sai, a conversa fica segura e a fila entrega depois', :aggregate_failures do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      antes_do_servico { parar_area! }
      allow(Crm::Ai::HandoffMemberSelector).to receive(:new).and_raise(RuntimeError) # a reserva sem IA quebra

      conversation.bot_handoff!

      expect(Rails.configuration.dispatcher).to aviso_de_passagem_para_pessoa
      conversation.reload
      expect(conversation.assignee_id).to be_nil
      expect(Crm::Entrega::Marca.dados(conversation)).to include('modo' => 'segurando', 'motivo' => 'robo_pediu', 'falha' => 'erro_na_passagem')

      allow(Crm::Ai::HandoffMemberSelector).to receive(:new).and_call_original
      with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::Ai::HandoffDrainJob.perform_now }

      expect(conversation.reload.assignee_id).to eq(ana.id)
      expect(Crm::Entrega::Marca.presente?(conversation)).to be(false)
    end

    # Pega: erro de contrato (pedida_por com por: :crm) virar desvio silencioso para a equipe.
    it 'erro de contrato com o serviço dos Agentes sobe, em vez de virar recusa' do
      allow(servico).to receive(:call).and_raise(ArgumentError)

      expect { entrega }.to raise_error(ArgumentError)
    end

    # Pega: o vínculo da área sumir entre a leitura e a passagem deixava a conversa com o robô que já tinha passado.
    it 'na passagem do robô, o vínculo some logo antes (sem_vinculo_na_caixa): alguém da equipe recebe e o aviso sai', :aggregate_failures do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      antes_do_servico { area_sumiu! }

      conversation.bot_handoff!

      expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
      expect(Rails.configuration.dispatcher).to aviso_de_passagem_para_pessoa
    end
  end

  describe 'pedido pelo nome (a IA do CRM decide; aqui é a lista que ela recebeu)' do
    let(:rotulo) { "#{area.name}#{Crm::AgentesIa::SUFIXO}" }

    # Pega: "quero falar com a Área Suporte" com ela sendo agente de IA ia para uma pessoa.
    it 'com o rótulo do agente, vai para o agente' do
      regra!('mode' => 'direct')

      expect(entrega(sugestao: rotulo).status).to eq(:com_ia)
    end

    it 'com o nome de uma pessoa, segue para a pessoa' do
      regra!('mode' => 'direct')

      expect(entrega(sugestao: 'Ana Vendas').pessoa).to eq(ana)
    end

    # Pega: o rótulo do agente casar por pedaço com uma pessoa de mesmo nome quando o agente não pôde receber.
    it 'agente pedido mas parado: rodízio entre pessoas, sem casar o rótulo com a pessoa de mesmo nome' do
      xara = create(:user, account: account, role: :agent, name: area.name)
      create(:inbox_member, inbox: inbox, user: xara)
      create(:conversation, account: account, inbox: inbox, assignee: xara, status: :open)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online', xara.id.to_s => 'online' })
      regra!('mode' => 'direct')
      parar_area!

      expect(entrega(sugestao: rotulo).pessoa).to eq(ana)
    end

    # Pega: a IA entrando no rodízio. Sem "pelo nome", o rótulo é ignorado.
    it 'rodízio ("Alguém da equipe") nunca escolhe o agente', :aggregate_failures do
      regra!('mode' => 'round_robin')

      expect(entrega(sugestao: rotulo).pessoa).to eq(ana)
      expect(servico).not_to have_received(:call)
    end
  end
end
