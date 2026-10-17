require 'rails_helper'
require 'timeout'

# #1428 — a versão guarda o AGENTE INTEIRO e voltar a ela devolve tudo. Caso real (13/10, conta 16): o
# Construtor "aplicou" uma pergunta e regravou o agente sem deixar versão; não havia como saber o que
# mudou nem como voltar.
RSpec.describe Autonomia::Agents::AgentVersioning do
  # A versão do agente inteiro vale só no piloto (Fase 2 dos Agentes); fora dele, ver 'fora do piloto'.
  let(:account) { conta_da_fase2 }
  let(:user) { create(:user, account: account) }

  let(:campos) { Autonomia::Agents::AgentVersioning::CAMPOS }
  let(:rascunho) { Autonomia::Agents::Agent.create!(account: account, name: 'Rascunho', agent_type: 'custom') }

  def gerado(sufixo, voz: 'feminina')
    {
      'name' => "Bia #{sufixo}", 'agent_type' => 'support', 'instruction' => "instrucao #{sufixo}",
      'scaffold' => "andaime #{sufixo}", 'human_card' => "cartao #{sufixo}", 'greeting' => "oi #{sufixo}",
      'fallback_message' => "nao sei #{sufixo}", 'handoff_rule' => "passa #{sufixo}",
      'starter_questions' => ["pergunta #{sufixo}"], 'tone' => "tom #{sufixo}",
      'guardrails' => ["limite #{sufixo}"], 'voice' => voz
    }
  end

  def aplicar(agent, parsed, extra = {})
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: user,
                                                    status: :processing, build_token: SecureRandom.hex(4))
    agent.apply_builder_config!(thread.build_token, Autonomia::Agents::Builder.map_attributes(parsed).merge(extra))
  end

  # O estado do agente nos campos versionados, lido do banco.
  def retrato(agent)
    agent.reload
    campos.index_with { |campo| agent[campo] }
          .merge('instruction' => agent.instruction, 'guardrails' => agent.config['guardrails'],
                 'voice' => agent.config['voice'], 'with_knowledge' => agent.config['with_knowledge'])
  end

  describe 'aplicação do Construtor' do
    it 'a criação grava exatamente 1 versão com o agente inteiro' do
      # Act
      aplicar(rascunho, gerado('v1'))

      # Assert
      versoes = rascunho.instruction_versions
      expect(versoes.count).to eq(1)
      versao = versoes.first
      expect([versao.reason, versao.created_by, versao.instruction]).to eq(['builder_create', user, 'instrucao v1'])
      expect(versao.metadata['agente'].keys).to match_array(campos + %w[config actuation])
      expect(versao.metadata['agente']).to include('name' => 'Bia v1', 'scaffold' => 'andaime v1', 'tone' => 'tom v1',
                                                   'starter_questions' => ['pergunta v1'], 'agent_type' => 'support')
      expect(versao.metadata['agente']['config'])
        .to eq('guardrails' => ['limite v1'], 'voice' => 'feminina', 'with_knowledge' => nil)
      expect(versao.metadata).not_to have_key('sem_mudanca')
    end

    it 'o ajuste grava exatamente 1 versão por aplicação' do
      # Arrange
      aplicar(rascunho, gerado('v1'))

      # Act
      aplicar(rascunho, gerado('v2'))

      # Assert
      expect(rascunho.instruction_versions.order(:id).pluck(:reason)).to eq(%w[builder_create builder_adjust])
      expect(rascunho.instruction_versions.order(:id).last.metadata['agente']['greeting']).to eq('oi v2')
    end

    it 'grava a versão mesmo quando nada mudou, marcando sem_mudanca' do
      # Arrange
      aplicar(rascunho, gerado('v1'))

      # Act
      aplicar(rascunho, gerado('v1'))

      # Assert
      ultima = rascunho.instruction_versions.order(:id).last
      expect(rascunho.instruction_versions.count).to eq(2)
      expect(ultima.reason).to eq('builder_adjust')
      expect(ultima.metadata['sem_mudanca']).to be(true)
    end

    it 'a primeira aplicação num agente sem versão grava antes a versão base com o estado anterior' do
      # Arrange — agente que já existia antes das versões completas
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Antigo', agent_type: 'support',
                                               instruction: 'instrucao antiga', greeting: 'oi antigo',
                                               config: { 'guardrails' => ['antigo'] })

      # Act
      aplicar(agent, gerado('v2'))

      # Assert
      base, aplicacao = agent.instruction_versions.order(:id).to_a
      expect(agent.instruction_versions.count).to eq(2)
      expect(base.reason).to eq('base')
      expect(base.instruction).to eq('instrucao antiga')
      expect(base.metadata['agente']).to include('name' => 'Antigo', 'greeting' => 'oi antigo')
      expect(base.metadata['agente']['config']).to include('guardrails' => ['antigo'])
      expect(aplicacao.reason).to eq('builder_adjust')
    end

    it 'grava a versão base quando só existem versões antigas, só com a instrução' do
      # Arrange
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Antigo', agent_type: 'support',
                                               instruction: 'instrucao antiga')
      agent.instruction_versions.create!(account: account, instruction: 'instrucao antiga', reason: 'kb_refresh',
                                         instruction_hash: Digest::SHA256.hexdigest('instrucao antiga'))

      # Act
      aplicar(agent, gerado('v2'))

      # Assert
      expect(agent.instruction_versions.order(:id).pluck(:reason)).to eq(%w[kb_refresh base builder_adjust])
    end

    it 'aplica sem versão quando o Construtor não devolve instrução' do
      # Act
      venceu = aplicar(rascunho, gerado('v1').merge('instruction' => ''))

      # Assert
      expect(venceu).to be(true)
      expect(rascunho.reload.name).to eq('Bia v1')
      expect(rascunho.instruction_versions.count).to eq(0)
    end

    # Conferência do #1428, sonda B: a saudação editada à mão era sobrescrita pelo ajuste sem versão do antes.
    it 'guarda o estado editado à mão (base) antes de um ajuste que muda campos' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      rascunho.update!(greeting: 'oi escrito a mao')

      # Act
      aplicar(rascunho, gerado('v2'))

      # Assert
      versoes = rascunho.instruction_versions.order(:id)
      expect(versoes.pluck(:reason)).to eq(%w[builder_create base builder_adjust])
      expect(versoes.second.metadata['agente']['greeting']).to eq('oi escrito a mao')
    end

    it 'não grava base quando o estado atual já é a última versão da lista' do
      # Arrange
      aplicar(rascunho, gerado('v1'))

      # Act
      aplicar(rascunho, gerado('v2'))

      # Assert
      expect(rascunho.instruction_versions.where(reason: 'base')).not_to exist
    end

    it 'não grava versão quando a aplicação perde para um ajuste mais novo' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      velha = Autonomia::Agents::BuildThread.create!(account: account, agent: rascunho, status: :processing,
                                                     build_token: 'velho')
      Autonomia::Agents::BuildThread.create!(account: account, agent: rascunho, status: :open)

      # Act
      venceu = rascunho.apply_builder_config!(velha.build_token,
                                              Autonomia::Agents::Builder.map_attributes(gerado('v2')))

      # Assert
      expect(venceu).to be(false)
      expect(rascunho.instruction_versions.count).to eq(1)
    end
  end

  describe 'voltar a uma versão' do
    it 'devolve o agente idêntico, campo a campo' do
      # Arrange
      aplicar(rascunho, gerado('v1', voz: 'masculina'))
      esperado = retrato(rascunho)
      versao_v1 = rascunho.instruction_versions.order(:id).last
      aplicar(rascunho, gerado('v2'))
      expect(retrato(rascunho)).not_to eq(esperado)

      # Act
      rascunho.restore_instruction!(versao_v1, created_by: user)

      # Assert
      expect(retrato(rascunho)).to eq(esperado)
      volta = rascunho.instruction_versions.order(:id).last
      expect(volta.reason).to eq('rollback')
      expect(volta.metadata['agente']['greeting']).to eq('oi v1')
    end

    it 'preserva as chaves de config que a versão não guarda' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      aplicar(rascunho, gerado('v2'))
      rascunho.update!(config: rascunho.config.merge('topic_map' => { 'precos' => 1 }, 'model' => 'x'))

      # Act
      rascunho.restore_instruction!(versao_v1)

      # Assert
      expect(rascunho.reload.config).to include('topic_map' => { 'precos' => 1 }, 'model' => 'x',
                                                'guardrails' => ['limite v1'])
    end

    it 'uma versão antiga, só com a instrução, restaura só a instrução' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      antiga = rascunho.instruction_versions.create!(account: account, instruction: 'instrucao antiga',
                                                     reason: 'kb_refresh',
                                                     instruction_hash: Digest::SHA256.hexdigest('instrucao antiga'))
      antes = retrato(rascunho)

      # Act
      rascunho.restore_instruction!(antiga)

      # Assert
      expect(retrato(rascunho)).to eq(antes.merge('instruction' => 'instrucao antiga'))
    end

    # Revisão do #1428 (ALTO): o PATCH só grava versão quando a instrução muda em modo manual; a saudação
    # editada à mão não estava em versão nenhuma e voltar a apagava sem rastro.
    it 'guarda o estado atual antes de voltar quando ele não está em versão nenhuma' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      aplicar(rascunho, gerado('v2'))
      rascunho.update!(greeting: 'oi escrito a mao')

      # Act
      rascunho.restore_instruction!(versao_v1, created_by: user)

      # Assert
      motivos = rascunho.instruction_versions.order(:id).pluck(:reason)
      expect(motivos).to eq(%w[builder_create builder_adjust antes_de_voltar rollback])
      antes = rascunho.instruction_versions.find_by(reason: 'antes_de_voltar')
      expect([antes.metadata['agente']['greeting'], antes.created_by]).to eq(['oi escrito a mao', user])
      expect(rascunho.reload.greeting).to eq('oi v1')
    end

    it 'não duplica o estado atual quando ele já é a última versão' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      aplicar(rascunho, gerado('v2'))

      # Act
      rascunho.restore_instruction!(versao_v1)

      # Assert
      expect(rascunho.instruction_versions.where(reason: 'antes_de_voltar')).not_to exist
    end

    # Revisão do #1428 + #1484: voltar a uma versão guiada num agente que hoje é manual devolve o modo junto;
    # a instrução gerada pelo Construtor nunca fica num agente manual, onde a API a mostraria.
    it 'voltar a uma versão guiada num agente manual devolve o modo guiado' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      guiada = rascunho.instruction_versions.order(:id).last
      rascunho.update!(mode: :manual, instruction: 'escrita pelo dono', scaffold: 'andaime manual')

      # Act
      rascunho.restore_instruction!(guiada)

      # Assert
      rascunho.reload
      expect([rascunho.mode, rascunho.instruction, rascunho.scaffold]).to eq(['guided', 'instrucao v1', 'andaime v1'])
      expect(guiada.metadata['agente']['mode']).to eq('guided')
    end

    it 'devolve with_knowledge e não devolve a atuação' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      rascunho.update!(actuation: :both, config: rascunho.config.merge('with_knowledge' => false))

      # Act
      rascunho.restore_instruction!(versao_v1)

      # Assert
      rascunho.reload
      expect(rascunho.config['with_knowledge']).to be_nil
      expect(rascunho.actuation).to eq('both')
      expect(versao_v1.metadata['agente']['actuation']).to eq('external')
    end

    it 'só a atuação mudada já conta como mudança na aplicação do Construtor' do
      # Arrange
      aplicar(rascunho, gerado('v1'))

      # Act — o Construtor grava a atuação escolhida na abertura junto com o resto (Builder#build_attributes)
      aplicar(rascunho, gerado('v1'), actuation: 'both')

      # Assert
      expect(rascunho.instruction_versions.order(:id).last.metadata).not_to have_key('sem_mudanca')
    end

    # Conferência do #1428, sonda A (#1484): agente manual voltando a uma versão cuja instrução não é do
    # dono (antiga, sem retrato, ou com retrato inválido) saía manual, com a instrução do Construtor à mostra.
    describe 'versão cuja instrução não é do dono' do
      before do
        aplicar(rascunho, gerado('v1'))
        rascunho.update!(mode: :manual, instruction: 'escrita pelo dono')
      end

      def versao_antiga(reason, metadata = {})
        rascunho.instruction_versions.create!(account: account, instruction: 'gerada pelo construtor', reason: reason,
                                              instruction_hash: Digest::SHA256.hexdigest('gerada pelo construtor'),
                                              metadata: metadata)
      end

      it 'sem retrato (kb_refresh antiga): o agente volta guiado e a volta fica oculta' do
        # Act
        rascunho.restore_instruction!(versao_antiga('kb_refresh'))

        # Assert
        rascunho.reload
        expect([rascunho.mode, rascunho.instruction]).to eq(['guided', 'gerada pelo construtor'])
        volta = rascunho.instruction_versions.order(:id).last
        expect([volta.reason, volta.instrucao_visivel?]).to eq(['rollback', false])
      end

      it 'com retrato inválido: o agente volta guiado' do
        # Act
        rascunho.restore_instruction!(versao_antiga('builder_adjust', 'agente' => { 'config' => 'texto' }))

        # Assert
        expect(rascunho.reload.mode).to eq('guided')
      end

      # Revisão do #1428 (MÉDIO): versão do Construtor gravada em modo manual deixava o agente manual.
      it 'versão do Construtor gravada em modo manual: o agente volta guiado e a instrução fica oculta' do
        # Arrange
        versao = versao_antiga('builder_adjust', 'agente' => rascunho.send(:retrato_da_versao))

        # Act
        rascunho.restore_instruction!(versao)

        # Assert
        expect([versao.metadata['agente']['mode'], versao.instrucao_visivel?]).to eq(['manual', false])
        expect([rascunho.reload.mode, rascunho.instruction]).to eq(['guided', 'gerada pelo construtor'])
      end

      it 'edição manual antiga, sem retrato, continua manual' do
        # Act
        rascunho.restore_instruction!(versao_antiga('manual_edit'))

        # Assert
        expect(rascunho.reload.mode).to eq('manual')
      end
    end

    # Conferência do #1428, sonda C: a linha `sem_mudanca` (fora da lista) não conta como "estado guardado".
    it 'grava antes_de_voltar quando o estado atual só está numa versão escondida da lista' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      rascunho.update!(greeting: 'oi escrito a mao')
      escondida = rascunho.instruction_versions.create!(
        account: account, instruction: rascunho.instruction, reason: 'builder_adjust',
        instruction_hash: Digest::SHA256.hexdigest(rascunho.instruction),
        metadata: { 'agente' => rascunho.send(:retrato_da_versao), 'sem_mudanca' => true }
      )

      # Act
      rascunho.restore_instruction!(versao_v1)

      # Assert
      antes = rascunho.instruction_versions.na_lista.find_by(reason: 'antes_de_voltar')
      expect(antes.id).to be > escondida.id
      expect(antes.metadata['agente']['greeting']).to eq('oi escrito a mao')
    end

    it 'a edição à mão seguida de uma aplicação sem mudança continua numa versão da lista depois da volta' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      rascunho.update!(greeting: 'oi escrito a mao')
      aplicar(rascunho, gerado('v1').merge('greeting' => 'oi escrito a mao'))

      # Act
      rascunho.restore_instruction!(versao_v1)

      # Assert
      saudacoes = rascunho.instruction_versions.na_lista.map { |versao| versao.metadata['agente']['greeting'] }
      expect(saudacoes).to include('oi escrito a mao')
      expect(rascunho.reload.greeting).to eq('oi v1')
    end

    describe 'retrato inválido' do
      before { aplicar(rascunho, gerado('v1')) }

      def versao_com(agente)
        rascunho.instruction_versions.create!(account: account, instruction: 'instrucao velha', reason: 'kb_refresh',
                                              instruction_hash: Digest::SHA256.hexdigest('instrucao velha'),
                                              metadata: { 'agente' => agente })
      end

      it 'com config que não é hash, restaura só a instrução e registra' do
        # Arrange
        versao = versao_com(rascunho.instruction_versions.last.metadata['agente'].merge('config' => 'texto'))
        antes = retrato(rascunho)
        allow(Rails.logger).to receive(:warn)

        # Act
        rascunho.restore_instruction!(versao)

        # Assert
        expect(retrato(rascunho)).to eq(antes.merge('instruction' => 'instrucao velha'))
        expect(Rails.logger).to have_received(:warn).with(/retrato invalido.*versao=#{versao.id}/)
      end

      it 'com agent_type fora da lista, restaura só a instrução' do
        # Arrange
        versao = versao_com(rascunho.instruction_versions.last.metadata['agente'].merge('agent_type' => 'hacker'))
        antes = retrato(rascunho)

        # Act
        rascunho.restore_instruction!(versao)

        # Assert
        expect(retrato(rascunho)).to eq(antes.merge('instruction' => 'instrucao velha'))
      end

      it 'com chave desconhecida, restaura só a instrução' do
        # Arrange
        versao = versao_com(rascunho.instruction_versions.last.metadata['agente'].merge('status' => 'active'))
        antes = retrato(rascunho)

        # Act
        rascunho.restore_instruction!(versao)

        # Assert
        expect(retrato(rascunho)).to eq(antes.merge('instruction' => 'instrucao velha'))
      end
    end
  end

  # Revisão do #1428 (BAIXO): a volta pedida enquanto uma aplicação do Construtor está em andamento. Sem a
  # trava (`lock!`) a volta decide pelo agente que tinha na memória — a saudação editada à mão — e grava
  # um 'antes_de_voltar' falso no meio do ajuste, com um estado que já não era o do agente. Com a trava, espera
  # o ajuste terminar, relê o agente e vê que o estado atual já está na versão do ajuste.
  describe 'voltar durante uma aplicação do Construtor', :relationships_committed_fixtures do
    self.use_transactional_tests = false

    let!(:account) { conta_da_fase2 }
    let!(:user) { create(:user, account: account) }
    let(:workers) { [] }
    let(:liberar_construtor) { Queue.new }

    after do
      liberar_construtor << true
      workers.each { |worker| worker.join(1) || worker.kill.join }
    ensure
      Autonomia::Agents::InstructionVersion.where(account_id: account.id).delete_all
      Autonomia::Agents::BuildThread.where(account_id: account.id).delete_all
      Autonomia::Agents::Agent.where(account_id: account.id).delete_all
      account.account_users.destroy_all
      account.destroy!
      NotificationSetting.where(user_id: user.id).delete_all
      AccessToken.where(owner: user).delete_all
      user.destroy!
      Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
    end

    def em_conexao_propria(pids)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |conexao|
          conexao.execute("SET lock_timeout = '5s'")
          pids << conexao.select_value('SELECT pg_backend_pid()')
          yield
        end
      end
    end

    def esperar_a_volta_travada(pid)
      Timeout.timeout(5) do
        sleep 0.02 until ActiveRecord::Base.connection.select_value(
          "SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = #{pid.to_i}"
        )
      end
    end

    it 'grava os motivos na ordem certa e não perde versão' do
      # Arrange — v1 aplicada, saudação editada à mão (fora de versão), ajuste v2 parado no meio da escrita
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      rascunho.update!(greeting: 'oi escrito a mao')
      ajuste = Autonomia::Agents::BuildThread.create!(account: account, agent: rascunho, created_by: user,
                                                      status: :processing, build_token: 'ajuste')
      do_construtor = Autonomia::Agents::Agent.find(rascunho.id)
      da_volta = Autonomia::Agents::Agent.find(rascunho.id)
      em_andamento = Queue.new
      liberar = liberar_construtor
      allow(do_construtor).to receive(:update!).and_wrap_original do |original, *args|
        em_andamento << true
        liberar.pop
        original.call(*args)
      end
      pids = Queue.new

      # Act
      workers << em_conexao_propria(pids) do
        do_construtor.apply_builder_config!(ajuste.build_token, Autonomia::Agents::Builder.map_attributes(gerado('v2')))
      end
      pids.pop
      em_andamento.pop
      workers << em_conexao_propria(pids) { da_volta.restore_instruction!(versao_v1, created_by: user) }
      esperar_a_volta_travada(pids.pop)
      liberar_construtor << true
      workers.each(&:join)

      # Assert
      versoes = rascunho.instruction_versions.order(:id).to_a
      expect(versoes.map(&:reason)).to eq(%w[builder_create base builder_adjust rollback])
      expect(versoes.map { |versao| versao.metadata['agente']['greeting'] })
        .to eq(['oi v1', 'oi escrito a mao', 'oi v2', 'oi v1'])
      expect(rascunho.reload.greeting).to eq('oi v1')
    end
  end

  describe '#1514: o Construtor não aplica em agente manual' do
    it 'recusa sob a trava quando o agente passou a manual durante a geração (objeto em memória ainda guiado)' do
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'G', agent_type: 'custom', instruction: 'antes')
      desatualizado = Autonomia::Agents::Agent.find(agent.id)
      agent.update!(mode: :manual)

      expect { aplicar(desatualizado, gerado('v1')) }.to raise_error(Autonomia::Agents::Agent::ModoManual)
      expect(agent.reload.instruction).to eq('antes')
    end

    it 'recusa no fechamento e não grava nada' do
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'M', agent_type: 'custom', mode: :manual,
                                               instruction: 'texto do dono')

      expect { aplicar(agent, gerado('v1')) }.to raise_error(Autonomia::Agents::Agent::ModoManual)
      expect(agent.reload.instruction).to eq('texto do dono')
      expect(agent.instruction_versions.count).to eq(0)
    end
  end

  # Revisão crítica (17/10): agente manual que recebeu o Construtor ANTES da recusa (dado legado) não pode expor a
  # instrução gerada nas versões base/antes_de_voltar/rollback. O texto só aparece se o dono o escreveu.
  describe 'a instrução só aparece quando o dono a escreveu' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'M', agent_type: 'custom', mode: :manual,
                                       instruction: 'texto do dono')
    end

    before { agent.record_instruction_version!(reason: 'manual_edit', created_by: user) }

    def legado_com_instrucao_gerada!
      agent.update_columns(instruction: 'GERADA pelo Construtor', greeting: 'oi') # rubocop:disable Rails/SkipsModelValidations
    end

    it 'antes_de_voltar e rollback de um agente manual com instrução gerada ficam ocultos' do
      legado_com_instrucao_gerada!
      agent.reload.restore_instruction!(agent.instruction_versions.find_by(reason: 'manual_edit'))

      antes = agent.instruction_versions.find_by(reason: 'antes_de_voltar')
      expect(antes.instruction).to eq('GERADA pelo Construtor')
      expect(antes.instrucao_visivel?).to be(false)
    end

    it 'a volta ao texto do dono mostra o texto (é dele)' do
      legado_com_instrucao_gerada!
      agent.reload.restore_instruction!(agent.instruction_versions.find_by(reason: 'manual_edit'))

      volta = agent.instruction_versions.find_by(reason: 'rollback')
      expect(volta.instruction).to eq('texto do dono')
      expect(volta.instrucao_visivel?).to be(true)
      expect(agent.reload).to be_manual
    end

    it 'voltar a uma versão de texto gerado num agente manual deixa o agente guiado' do
      legado_com_instrucao_gerada!
      agent.reload.restore_instruction!(agent.instruction_versions.find_by(reason: 'manual_edit'))
      gerada = agent.instruction_versions.find_by(reason: 'antes_de_voltar')

      agent.reload.restore_instruction!(gerada)

      expect(agent.reload).to be_guided
    end

    it 'a volta grava para qual versão foi' do
      alvo = agent.instruction_versions.find_by(reason: 'manual_edit')
      agent.update!(greeting: 'outra')

      agent.restore_instruction!(alvo)

      expect(agent.instruction_versions.find_by(reason: 'rollback').metadata['voltou_para']).to eq(alvo.id)
    end
  end

  describe 'fora do piloto (sem a Fase 2): como antes' do
    let(:account) { conta_da_fase2(ligada: false) }

    # Revisão crítica (17/10): versão antiga sem retrato com o texto do dono continua dele.
    it 'agente manual volta a uma versão antiga (sem retrato) com o texto do dono e continua manual, com o texto visível' do
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'M', agent_type: 'custom', mode: :manual,
                                               instruction: 'texto do dono')
      agent.record_instruction_version!(reason: 'manual_edit', created_by: user)
      antiga = agent.instruction_versions.create!(account: account, instruction: 'texto do dono',
                                                  instruction_hash: Digest::SHA256.hexdigest('texto do dono'),
                                                  reason: 'rollback', metadata: {})
      agent.update!(instruction: 'outro texto do dono')

      agent.restore_instruction!(antiga)

      expect(antiga.instrucao_visivel?).to be(true)
      expect(agent.reload).to have_attributes(instruction: 'texto do dono', mode: 'manual')
    end

    it 'o Construtor não grava versão' do
      aplicar(rascunho, gerado('v1'))

      expect(rascunho.instruction_versions.count).to eq(0)
    end

    it 'voltar devolve só a instrução, sem antes_de_voltar' do
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'G', agent_type: 'custom', instruction: 'v1',
                                               greeting: 'oi 1')
      agent.record_instruction_version!(reason: 'kb_refresh')
      alvo = agent.instruction_versions.last
      agent.update!(instruction: 'v2', greeting: 'oi 2')

      agent.restore_instruction!(alvo)

      expect(agent.reload).to have_attributes(instruction: 'v1', greeting: 'oi 2')
      expect(agent.instruction_versions.pluck(:reason)).to eq(%w[kb_refresh rollback])
    end
  end

  # Declarado no PR: a versão da aplicação é gravada na mesma transação da escrita do Construtor. Se ela falhar,
  # a aplicação inteira falha (o ajuste não fica sem rastro).
  it 'se a versão não puder ser gravada, a aplicação do Construtor não acontece' do
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'G', agent_type: 'custom', instruction: 'antes')
    # Sem o hash, a versão não passa na validação (`instruction_hash` obrigatório).
    allow(Digest::SHA256).to receive(:hexdigest).and_return(nil)

    expect { aplicar(agent, gerado('v1')) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(agent.reload.instruction).to eq('antes')
  end
end
