require 'rails_helper'

# O QUE MUDA PARA O CONTRATADO EM CADA LEITOR DE `Agent#instrucao_mantida?` (#3211, Tarefa 8, R1).
#
# Estender o predicado ao contratado mudou cada lugar que o lê sem escrever a instrução. Um exemplo por leitor, com a
# decisão escrita no nome: a maioria é desejada (a instrução e a base do contratado são nossas, como as da Lia); os dois
# leitores do CRM NÃO seguem o predicado — no CRM o contratado é agente comum e só a Lia fica protegida
# (`Agent#protegido_no_crm?`, decisão do Rodrigo em 24/11). O contratado é criado à mão com a marca: o `Contratar` só
# existe na Tarefa 20. Cada leitor é comparado com um agente comum, para o exemplo provar que é o predicado que decide.
# rubocop:disable RSpec/DescribeClass -- os leitores são de vários arquivos (controllers, serviços, CRM), não uma classe
RSpec.describe 'Leitores de Agent#instrucao_mantida? com o agente contratado' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca })
  end
  let(:comum) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'instrução da Ana')
  end
  let(:lia) do
    Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Corretora Exemplo').call
  end
  let(:vinculo_contratado) { vincular(contratado) }
  let(:vinculo_lia) { vincular(lia) }
  let(:mantida) { Autonomia::Agents::Agent::InstrucaoMantida }

  before { allow(Autonomia::Agents::Fase2).to receive(:ligada?).and_return(true) }

  def vincular(agente)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: create(:inbox, account: account), account: account,
                                          agent_bot: create(:agent_bot, account: account))
  end

  def controlador(classe, params = {}, agente: nil)
    classe.new.tap do |controller|
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(params))
      controller.instance_variable_set(:@agent, agente)
    end
  end

  def material(agente)
    Autonomia::Agents::Source.new(account: account, agent: agente)
  end

  it 'o contratado tem a instrução mantida e não é protegido no CRM' do
    expect(contratado.instrucao_mantida?).to be(true)
    expect(contratado.protegido_no_crm?).to be(false)
  end

  describe 'leitores que passam a recusar o contratado (desejado)' do
    it 'agents#update (agents_controller.rb:170-171): recusa editar instrução, modo e tipo' do
      klass = Api::V1::Accounts::Autonomia::AgentsController
      [{ instruction: 'x' }, { mode: 'manual' }, { agent_type: 'custom' }, { agent_type: 'insurance_quote' }].each do |pedido|
        expect { controlador(klass, { agent: pedido }, agente: contratado).send(:rejeitar_edicao_da_instrucao_mantida) }
          .to raise_error(mantida)
      end
      expect { controlador(klass, { agent: { instruction: 'x' } }, agente: comum).send(:rejeitar_edicao_da_instrucao_mantida) }
        .not_to raise_error
    end

    it 'agents#create (agents_controller.rb:189): o tipo pedido não vira mantido, a marca não chega pelo tipo' do
      controller = controlador(Api::V1::Accounts::Autonomia::AgentsController)
      expect(controller.send(:instrucao_mantida_pelo_tipo?, 'sdr')).to be(false)
      expect(controller.send(:instrucao_mantida_pelo_tipo?, 'insurance_quote')).to be(true)
    end

    it 'build_threads#fetch_thread (build_threads_controller.rb:158): recusa a conversa do Construtor' do
      thread = Autonomia::Agents::BuildThread.create!(account: account, agent: contratado)
      controller = controlador(Api::V1::Accounts::Autonomia::Agents::BuildThreadsController, { id: thread.id })
      allow(controller).to receive(:build_threads_scope).and_return(Autonomia::Agents::BuildThread.where(account: account))
      expect { controller.send(:fetch_thread) }.to raise_error(mantida)
    end

    it 'build_threads#create (build_threads_controller.rb:208): recusa abrir o Construtor no contratado' do
      klass = Api::V1::Accounts::Autonomia::Agents::BuildThreadsController
      escopo = Autonomia::Agents::Agent.where(account: account)
      controller = controlador(klass, { build_thread: { autonomia_agent_id: contratado.id } })
      allow(controller).to receive(:agents_scope).and_return(escopo)
      expect { controller.send(:thread_params) }.to raise_error(mantida)

      outro = controlador(klass, { build_thread: { autonomia_agent_id: comum.id } })
      allow(outro).to receive(:agents_scope).and_return(escopo)
      expect(outro.send(:thread_params)).to eq(agent: comum)
    end

    it 'playground (playground_controller.rb:48): não confere as fotos do teste' do
      klass = Api::V1::Accounts::Autonomia::Agents::PlaygroundController
      expect(controlador(klass, agente: contratado).send(:conferir_fotos?)).to be(false)
      expect(controlador(klass, agente: comum).send(:conferir_fotos?)).to be(true)
    end

    it 'sources (sources_controller.rb:60): não relê na Fase 2 enquanto lê' do
      klass = Api::V1::Accounts::Autonomia::Agents::SourcesController
      [[contratado, false], [comum, true]].each do |agente, esperado|
        fonte = material(agente)
        allow(fonte).to receive(:lendo_agora?).and_return(true)
        controller = controlador(klass)
        controller.instance_variable_set(:@source, fonte)
        expect(controller.send(:lendo_na_fase2?)).to be(esperado)
      end
    end

    it 'sources (sources_controller.rb:146): não recebe foto como material (a base é nossa)' do
      klass = Api::V1::Accounts::Autonomia::Agents::SourcesController
      expect(controlador(klass, agente: contratado).send(:recusa_da_foto_no_agente, 'knowledge')).to eq('foto_agente_de_cotacao')
      expect(controlador(klass, agente: comum).send(:recusa_da_foto_no_agente, 'knowledge')).to be_nil
    end

    it 'base_de_seguros.rb:25: sem a linha de troca da base de seguros' do
      expect(Autonomia::Agents::BaseDeSeguros.elegivel?(contratado)).to be(false)
      expect(Autonomia::Agents::BaseDeSeguros.elegivel?(comum)).to be(true)
    end

    it 'material.rb:11: sem as conferências do material' do
      expect(Autonomia::Agents::Material.conferir?(contratado)).to be(false)
      expect(Autonomia::Agents::Material.conferir?(comum)).to be(true)
    end

    it 'knowledge/resumo_por_secao.rb:84: sem o índice por seção da Fase 2' do
      resumo = ->(agente) { Autonomia::Agents::Knowledge::ResumoPorSecao.new(source: material(agente), token: 't') }
      expect(resumo.call(contratado).send(:material_da_fase2?)).to be(false)
      expect(resumo.call(comum).send(:material_da_fase2?)).to be(true)
    end

    it 'knowledge/fotos_da_criacao.rb:31: sem foto da criação na base' do
      fotos = lambda do |agente|
        Autonomia::Agents::Knowledge::FotosDaCriacao.new(Autonomia::Agents::BuildThread.create!(account: account, agent: agente))
      end
      expect(fotos.call(contratado).send(:criacao_na_fase2?)).to be(false)
      expect(fotos.call(comum).send(:criacao_na_fase2?)).to be(true)
    end

    it 'knowledge/processors/pdf.rb:78,87: o PDF fica com a leitura da main, como a Lia' do
      pdf = ->(agente) { Autonomia::Agents::Knowledge::Processors::Pdf.new(material(agente)) }
      expect(pdf.call(contratado).send(:em_paragrafos?)).to be(false)
      expect(pdf.call(contratado).send(:agente_protegido?)).to be(true)
      expect(pdf.call(comum).send(:em_paragrafos?)).to be(true)
      expect(pdf.call(comum).send(:agente_protegido?)).to be(false)
    end

    it 'knowledge/instruction_refresher.rb:72: sem refresh da instrução (sai antes do modelo)' do
      allow(Autonomia::Agents::Config).to receive(:instruction_auto_refresh?).and_return(true)
      allow(Rails.logger).to receive(:info).and_call_original
      allow(Crm::Ai::ResponsesClient).to receive(:new)

      expect(Autonomia::Agents::Knowledge::InstructionRefresher.call(contratado, reason: :kb_changed)).to be_nil
      expect(Rails.logger).to have_received(:info).with(include('status=skipped_instrucao_mantida'))
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'os escritores da coluna recusam o contratado (a guarda única recusar_se_instrucao_mantida!)' do
      expect { contratado.restore_instruction!(nil) }.to raise_error(mantida)
      expect { contratado.trocar_base!({}) }.to raise_error(mantida)
      expect { contratado.desfazer_troca_da_base! }.to raise_error(mantida)
      expect { contratado.desfazer_ajuste!(thread: nil) }.to raise_error(mantida)
      expect do
        contratado.desfazer_do_construtor!(versoes: {}, colunas: [], chaves: [], esperado: nil, geracao: nil)
      end.to raise_error(mantida)
    end
  end

  describe 'leitores do CRM: o contratado é agente comum, só a Lia fica protegida (Rodrigo, 24/11)' do
    it 'F1: a fala do contratado conta como a de agente comum' do
      expect(Crm::Ai::FatosDaConversa.send(:agente_protegido?, account.id, vinculo_contratado.agent_bot_id)).to be(false)
    end

    it 'F1: a Lia continua protegida' do
      expect(Crm::Ai::FatosDaConversa.send(:agente_protegido?, account.id, vinculo_lia.agent_bot_id)).to be(true)
    end

    it 'promessa: o CRM cumpre a promessa do contratado e não a da Lia' do
      expect(contratado.protegido_no_crm?).to be(false)
      expect(lia.protegido_no_crm?).to be(true)
    end
  end
end
