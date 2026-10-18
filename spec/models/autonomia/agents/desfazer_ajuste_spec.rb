require 'rails_helper'

# #1428 (tema 6, parte 3) — o Desfazer do último ajuste do "Mudar conversando" no piloto: volta exato à versão de antes,
# vale até a próxima mudança no agente, e as duas versões (a aplicada e a da volta) ficam na lista.
RSpec.describe Autonomia::Agents::DesfazerAjuste do
  include_context 'with ajuste por lista'

  let(:builder) { Autonomia::Agents::Builder.new(account: account, build_thread: thread) }
  let(:user) { create(:user, account: account) }
  let(:mudancas) { [mudanca('tone', fala, 'Respostas curtas.'), mudanca('instruction', fala, 'No máximo 2 frases.')] }

  # O agente nos campos versionados e no config inteiro (inclusive chave que o Construtor não escreve).
  def retrato
    agent.reload
    Autonomia::Agents::AgentVersioning::CAMPOS.index_with { |campo| agent[campo] }
                                              .merge('instruction' => agent.instruction, 'config' => agent.config)
  end

  def aplicar_ajuste
    respostas << saida('tone' => 'cordial e curto', 'instruction' => 'Responda em no máximo 2 frases.',
                       'greeting' => 'Olá!', 'guardrails' => ['Nunca fale de preço.'], 'mudancas' => mudancas)
    run_turn
  end

  def desfazer
    agent.reload.desfazer_ajuste!(thread: thread.reload, created_by: user)
  end

  before { agent.update!(config: agent.config.merge('model' => 'gpt-x', 'topic_map' => { 'a' => 1 })) }

  describe 'o fechamento do ajuste' do
    it 'guarda no state a versão de antes, a da aplicação e a conferência do turno' do
      aplicar_ajuste

      base = agent.instruction_versions.find_by!(reason: 'base')
      expect(estado['ultimo_ajuste']).to eq('versao_antes_id' => base.id, 'versao_id' => versoes_do_construtor.sole.id,
                                            'conferencia' => estado['conferencia'])
    end

    it 'com correção, a versão do Desfazer é a da correção' do
      preco = 'preço passa para a equipe'
      respostas << saida('tone' => 'cordial e curto', 'mudancas' => [mudanca('tone', fala, 'Curto.'), mudanca('handoff_rule', preco)])
      respostas << saida('handoff_rule' => 'Preço vai para a equipe.', 'mudancas' => [mudanca('handoff_rule', preco)])
      conferencias << { nao: [1] }

      run_turn

      expect(estado['ultimo_ajuste']['versao_id']).to eq(versoes_do_construtor.last.id)
      expect(agent.reload.conversa_desfazivel).to eq(thread)
    end

    it 'uma pergunta na mesma conversa não tira o Desfazer' do
      aplicar_ajuste
      thread.append_message!('user', 'O que ele responde sobre preço?')
      respostas << saida('so_pergunta' => true, 'next_question' => 'Ele passa para a equipe.')

      run_turn

      expect(estado).to include('conferencia' => nil)
      expect(estado['ultimo_ajuste']).to be_present
      expect(agent.reload.conversa_desfazivel).to eq(thread)
      expect(desfazer).to be(true)
      expect(agent.reload.tone).to eq('cordial')
    end

    it 'uma pergunta numa sessão nova não tira o Desfazer' do
      aplicar_ajuste
      nova = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
      nova.append_message!('user', 'O que ele responde sobre preço?')
      respostas << saida('so_pergunta' => true, 'next_question' => 'Ele passa para a equipe.')
      outro = Autonomia::Agents::Builder.new(account: account, build_thread: nova)
      allow(outro).to receive_messages(credential: { api_key: 'k' }, client: fake_client, cliente_da_correcao: fake_client)

      outro.run!(nova.begin_build!)

      expect(nova.reload).to be_ready
      expect(agent.reload.conversa_desfazivel).to eq(thread)
      expect(desfazer).to be(true)
    end
  end

  describe '#desfazer_ajuste!' do
    it 'volta exato ao agente de antes, inclusive o config, e as duas versões ficam na lista' do
      antes = retrato
      aplicar_ajuste
      aplicada = versoes_do_construtor.sole

      expect(desfazer).to be(true)

      expect(retrato).to eq(antes)
      volta = agent.instruction_versions.order(:id).last
      base = agent.instruction_versions.find_by!(reason: 'base')
      expect(volta).to have_attributes(reason: 'rollback', created_by: user)
      expect(volta.metadata).to include('voltou_para' => base.id, 'desfez_ajuste' => aplicada.id)
      expect(aplicada.reload.metadata).to include('desfeita' => true)
      expect(agent.instruction_versions.na_lista).to include(aplicada, volta)
      expect(estado['ultimo_ajuste']).to include('desfeito' => true)
    end

    it 'pedir de novo responde igual, sem versão nova' do
      aplicar_ajuste
      desfazer

      expect { expect(desfazer).to be(true) }.not_to(change { agent.instruction_versions.count })
    end

    it 'recusa quando o agente mudou depois do ajuste (o caminho é Versões)' do
      aplicar_ajuste
      agent.reload.update!(greeting: 'Editado à mão.')

      expect { desfazer }.to raise_error(described_class::AjusteMudou)
      expect(agent.reload.greeting).to eq('Editado à mão.')
      expect(agent.instruction_versions.where(reason: 'rollback')).to be_empty
    end

    # A instrução é campo versionado: voltar ao antes apagaria a reescrita da base. O Desfazer sai (o caminho é Versões).
    it 'a base reescrevendo a instrução tira o Desfazer' do
      aplicar_ajuste
      agent.reload.refresh_instruction!('Instrução nova pela base.', expected_instruction: agent.instruction)

      expect(agent.reload.conversa_desfazivel).to be_nil
    end

    it 'uma volta de versão tira o Desfazer' do
      aplicar_ajuste
      agent.reload.restore_instruction!(agent.instruction_versions.find_by!(reason: 'base'), created_by: user)

      expect(agent.reload.conversa_desfazivel).to be_nil
      expect { desfazer }.to raise_error(described_class::AjusteMudou)
    end

    it 'voltar depois para a versão desfeita tira a marca desfeita' do
      aplicar_ajuste
      aplicada = versoes_do_construtor.sole
      desfazer

      agent.reload.restore_instruction!(aplicada.reload, created_by: user)

      expect(aplicada.reload.metadata).not_to have_key('desfeita')
      expect(agent.reload.tone).to eq('cordial e curto')
      # Revisão adversarial F4: o agente não está mais no antes; pedir o Desfazer de novo não responde "desfeito".
      expect { desfazer }.to raise_error(described_class::AjusteMudou)
    end

    it 'ligar, desligar e mexer no que não é versionado não tiram o Desfazer; a restauração não mexe nisso' do
      aplicar_ajuste
      agent.reload.update!(enabled: false, config: agent.config.merge('topic_map' => { 'b' => 2 }))

      expect(desfazer).to be(true)
      expect(agent.reload).to have_attributes(enabled: false, tone: 'cordial')
      expect(agent.config['topic_map']).to eq('b' => 2)
    end

    # Revisão adversarial F3: o job em voo, de qualquer idade, perde o token; a escrita atrasada é recusada na guarda.
    it 'job em voo: o Desfazer toma o token e a escrita atrasada não regrava por cima' do
      aplicar_ajuste
      outra = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
      token = outra.begin_build!
      outra.update_columns(updated_at: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(desfazer).to be(true)

      expect(outra.reload).to be_failed
      expect(outra.state['error']).to eq(described_class::SUPERADA)
      expect(agent.reload.apply_builder_config!(token, { tone: 'escrita atrasada' })).to be(false)
      expect(agent.reload.tone).to eq('cordial')
    end

    # Custo (a volta por Versões vale para todas as contas): a trava não lê `messages`, que não tem teto.
    it 'o Desfazer e a volta travam as conversas só pelas colunas leves, em ordem de id' do
      aplicar_ajuste
      consultas = []
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') { |*, dados| consultas << dados[:sql] }
      begin
        desfazer
        agent.reload.restore_instruction!(agent.instruction_versions.find_by!(reason: 'base'), created_by: user)
      ensure
        ActiveSupport::Notifications.unsubscribe(assinatura)
      end

      tabela = '"autonomia_agent_build_threads"'
      travas = consultas.select { |sql| sql.include?(tabela) && sql.include?('FOR UPDATE') }
      expect(travas.size).to eq(2)
      expect(travas).to all(start_with("SELECT #{tabela}.\"id\", #{tabela}.\"status\", #{tabela}.\"build_token\" FROM")
                              .and(include("ORDER BY #{tabela}.\"id\" ASC"))
                              .and(include("#{tabela}.\"account_id\" = ")))
      expect(travas.join).not_to include('messages')
    end

    it 'a chave do config que não existia antes sai, em vez de ficar nil' do
      agent.update!(config: agent.config.except('voice'))
      respostas << saida('voice' => 'feminina', 'mudancas' => [mudanca('voice', fala, 'Voz feminina.')])
      run_turn
      expect(agent.reload.config['voice']).to eq('feminina')

      desfazer

      expect(agent.reload.config).not_to have_key('voice')
    end

    it 'recusa a conversa antiga mesmo quando a mais nova também poderia desfazer' do
      aplicar_ajuste
      Autonomia::Agents::BuildThread.create!(account: account, agent: agent, status: :ready, state: thread.reload.state)

      expect { desfazer }.to raise_error(described_class::AjusteMudou)
      expect(agent.reload.tone).to eq('cordial e curto')
    end

    it 'a própria conversa gerando um turno novo: o Desfazer cancela o turno' do
      aplicar_ajuste
      thread.begin_build!

      expect(desfazer).to be(true)
      expect(thread.reload).to be_failed
      expect(thread.state['ultimo_ajuste']).to include('desfeito' => true)
    end

    it 'o Desfazer encerra o "tira isso" da conversa' do
      aplicar_ajuste
      thread.update_columns(state: thread.reload.state.merge('nao_pedido_anterior' => { 'campos' => ['greeting'] })) # rubocop:disable Rails/SkipsModelValidations

      desfazer

      expect(estado).not_to have_key('nao_pedido_anterior')
    end

    it 'recusa agente manual sem mexer em nada' do
      aplicar_ajuste
      agent.update_columns(mode: Autonomia::Agents::Agent.modes[:manual]) # rubocop:disable Rails/SkipsModelValidations

      expect { desfazer }.to raise_error(Autonomia::Agents::Agent::ModoManual)
      expect(agent.reload.tone).to eq('cordial e curto')
    end

    it 'recusa o Agente de Cotação' do
      aplicar_ajuste
      agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

      expect { desfazer }.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
      expect(agent.reload.tone).to eq('cordial e curto')
    end

    it 'fora do piloto não existe' do
      aplicar_ajuste
      Autonomia::Agents::Fase2.desligar!(account)

      expect { desfazer }.to raise_error(ActiveRecord::RecordNotFound)
      expect(agent.reload.tone).to eq('cordial e curto')
    end

    it 'recusa a conversa de outro agente' do
      aplicar_ajuste
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'support', instruction: 'x')

      expect { outro.desfazer_ajuste!(thread: thread.reload, created_by: user) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
