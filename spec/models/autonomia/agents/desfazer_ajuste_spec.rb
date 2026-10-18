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
    it 'guarda no state as versões e o updated_at que a escrita deixou' do
      aplicar_ajuste

      base = agent.instruction_versions.find_by!(reason: 'base')
      expect(estado['ultimo_ajuste']).to eq('versao_antes_id' => base.id, 'versao_id' => versoes_do_construtor.sole.id,
                                            'agente_updated_at' => agent.reload.updated_at.iso8601(6))
    end

    it 'com correção, a versão do Desfazer é a da correção' do
      preco = 'preço passa para a equipe'
      respostas << saida('tone' => 'cordial e curto', 'mudancas' => [mudanca('tone', fala, 'Curto.'), mudanca('handoff_rule', preco)])
      respostas << saida('handoff_rule' => 'Preço vai para a equipe.', 'mudancas' => [mudanca('handoff_rule', preco)])
      conferencias << { nao: [1] }

      run_turn

      expect(estado['ultimo_ajuste']['versao_id']).to eq(versoes_do_construtor.last.id)
      expect(estado['ultimo_ajuste']['agente_updated_at']).to eq(agent.reload.updated_at.iso8601(6))
    end

    it 'o turno seguinte que não aplica esquece o Desfazer' do
      aplicar_ajuste
      thread.append_message!('user', 'O que ele responde sobre preço?')
      respostas << saida('so_pergunta' => true, 'next_question' => 'Ele passa para a equipe.')

      run_turn

      expect(estado).to include('ultimo_ajuste' => nil, 'conferencia' => nil)
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

    it 'recusa quando há uma conversa mais nova do agente' do
      aplicar_ajuste
      Autonomia::Agents::BuildThread.create!(account: account, agent: agent)

      expect { desfazer }.to raise_error(described_class::AjusteMudou)
      expect(agent.reload.tone).to eq('cordial e curto')
    end

    it 'recusa enquanto a conversa está gerando' do
      aplicar_ajuste
      thread.begin_build!

      expect { desfazer }.to raise_error(described_class::AjusteMudou)
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
