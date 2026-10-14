require 'rails_helper'

# #1367: cada CHAMADA do Construtor é medida com o rótulo da sua fase. A chave de cache continua uma só por conta.
# PR 2: a pergunta da entrevista sai da chamada enxuta, com a busca desligada por tool_choice; o fechamento sai da
# chamada completa, com busca
# (detalhes em builder_coleta_enxuta_spec). O log do turno traz quantas chamadas houve e o resultado REAL
# (fechou/forced_close), que só existe depois do apply.
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:question_payload) do
    { 'needs_more_info' => true, 'next_question' => 'Qual o horário de atendimento?', 'user_asked_to_close' => false }
  end
  let(:model_payload) { question_payload }

  before do
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create) do
      { text: model_payload.to_json,
        usage: { 'output_tokens' => 900, 'output_tokens_details' => { 'reasoning_tokens' => 640 } },
        tools_used: [] }
    end
  end

  def run_turn
    with_modified_env(AI_WEB_SEARCH_ENABLED: 'true') { builder.run!(thread.begin_build!) }
  end

  def expect_client(feature)
    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(hash_including(feature: feature, cache_key: "agente_builder:#{account.id}"))
  end

  def expect_web_search_offered
    expect(fake_client).to have_received(:create).with(hash_including(tools: Crm::Ai::WebSearch::TOOL))
  end

  # A enxuta mantém a busca na lista (prefixo em cache) e a desliga por tool_choice: nenhuma chamada pode buscar.
  def expect_no_web_search
    expect(fake_client).to have_received(:create).with(hash_including(tool_choice: 'none'))
    expect(fake_client).not_to have_received(:create).with(hash_excluding(:tool_choice))
  end

  context 'when the turn is an interview question (coleta)' do
    before { thread.append_message!('user', 'Quero um agente de suporte') }

    it 'labels the usage as agente_builder_coleta, keeps the account cache key and turns web_search off' do
      run_turn

      expect_client('agente_builder_coleta')
      expect_no_web_search
    end
  end

  context 'when the turn is expected to close the interview (fechamento)' do
    it 'labels the usage as agente_builder_fechamento when the owner declared no material' do
      thread.update!(no_materials_declared: true)
      thread.append_message!('user', 'Não tenho material')

      run_turn

      expect_client('agente_builder_fechamento')
      expect_web_search_offered
    end

    it 'treats the exhausted interview budget as fechamento' do
      described_class::MAX_INTERVIEW_QUESTIONS.times { |i| thread.append_message!('user', "resposta #{i}") }

      run_turn

      expect_client('agente_builder_fechamento')
    end

    it 'keeps web_search off when the global switch is off' do
      thread.append_message!('user', 'Quero um agente de suporte')

      with_modified_env(AI_WEB_SEARCH_ENABLED: 'false') { builder.run!(thread.begin_build!) }

      expect(fake_client).to have_received(:create).with(hash_including(tools: nil))
    end
  end

  context 'when the agent already has a closed instruction (ajuste)' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(
        account: account, name: 'Agente vivo', agent_type: 'support', mode: :guided,
        status: :active, enabled: true, instruction: 'Instrução fechada do agente.'
      )
    end

    before do
      thread.update!(agent: agent)
      thread.append_message!('user', 'Troque a saudação')
    end

    it 'labels the usage as agente_builder_ajuste with the same account cache key' do
      run_turn

      expect_client('agente_builder_ajuste')
      expect_web_search_offered
    end
  end

  describe 'turn log' do
    before do
      thread.append_message!('user', 'Quero um agente de suporte')
      allow(Rails.logger).to receive(:info)
    end

    it 'records phase, number of calls, reasoning tokens, tools and the real outcome, without any content' do
      run_turn

      expect(Rails.logger).to have_received(:info).with(
        a_string_including("[autonomia][builder] turn thread=#{thread.id}", 'phase=coleta', 'calls=1',
                           'web_search_offered=false',
                           'reasoning_tokens=640', 'output_tokens=900', 'tools_used=', 'fechou=false',
                           'forced_close=false')
      )
      expect(Rails.logger).not_to have_received(:info).with(a_string_including('Quero um agente de suporte'))
    end

    context 'when the model reads an order to close in a collection turn' do
      let(:model_payload) do
        question_payload.merge(
          'user_asked_to_close' => true, 'name' => 'Ana', 'instruction' => 'Instrução completa.',
          'human_card' => 'A Ana atende.', 'greeting' => 'Oi!', 'tone' => 'cordial'
        )
      end

      it 'logs the two calls, the summed tokens and the real close under fechamento' do
        run_turn

        expect(Rails.logger).to have_received(:info).with(
          a_string_including('phase=fechamento', 'calls=2', 'web_search_offered=true', 'reasoning_tokens=1280',
                             'output_tokens=1800', 'fechou=true', 'forced_close=true')
        )
      end
    end
  end
end
