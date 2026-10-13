require 'rails_helper'

# #1367 (alavancas 0 e 1): cada turno do Construtor é medido com o rótulo da sua fase, e a busca na web
# só vai ao modelo quando o turno vai redigir ou ajustar a instrução. A fase é decidida ANTES da chamada,
# com os mesmos sinais que já escolhem o raciocínio (closing_phase?/adjust_mode?).
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:question_payload) do
    { 'needs_more_info' => true, 'next_question' => 'Qual o horário de atendimento?', 'user_asked_to_close' => false }
  end

  before do
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create).and_return(
      text: question_payload.to_json,
      usage: { 'output_tokens' => 900, 'output_tokens_details' => { 'reasoning_tokens' => 640 } },
      tools_used: []
    )
  end

  def run_turn
    with_modified_env(AI_WEB_SEARCH_ENABLED: 'true') { builder.run!(thread.begin_build!) }
  end

  def expect_feature(feature)
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: feature))
  end

  context 'when the turn is an interview question (coleta)' do
    before { thread.append_message!('user', 'Quero um agente de suporte') }

    it 'labels the usage as agente_builder_coleta' do
      run_turn

      expect_feature('agente_builder_coleta')
    end

    it 'does not offer web_search to the model' do
      run_turn

      expect(fake_client).to have_received(:create).with(hash_including(tools: nil))
    end
  end

  context 'when the turn is going to close the interview (fechamento)' do
    it 'labels the usage as agente_builder_fechamento and offers web_search when the owner declared no material' do
      thread.update!(no_materials_declared: true)
      thread.append_message!('user', 'Não tenho material')

      run_turn

      expect_feature('agente_builder_fechamento')
      expect(fake_client).to have_received(:create).with(hash_including(tools: Crm::Ai::WebSearch::TOOL))
    end

    it 'treats the exhausted interview budget as fechamento' do
      described_class::MAX_INTERVIEW_QUESTIONS.times { |i| thread.append_message!('user', "resposta #{i}") }

      run_turn

      expect_feature('agente_builder_fechamento')
      expect(fake_client).to have_received(:create).with(hash_including(tools: Crm::Ai::WebSearch::TOOL))
    end

    it 'keeps web_search off when the global switch is off' do
      thread.update!(no_materials_declared: true)
      thread.append_message!('user', 'Não tenho material')

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

    it 'labels the usage as agente_builder_ajuste and offers web_search' do
      run_turn

      expect_feature('agente_builder_ajuste')
      expect(fake_client).to have_received(:create).with(hash_including(tools: Crm::Ai::WebSearch::TOOL))
    end
  end

  describe 'turn log' do
    before { thread.append_message!('user', 'Quero um agente de suporte') }

    it 'records phase, reasoning tokens and the tools the model used, without any content' do
      allow(Rails.logger).to receive(:info)

      run_turn

      expect(Rails.logger).to have_received(:info).with(
        a_string_including("[autonomia][builder] turn thread=#{thread.id}", 'phase=coleta', 'web_search_offered=false',
                           'reasoning_tokens=640', 'output_tokens=900', 'tools_used=')
      )
      expect(Rails.logger).not_to have_received(:info).with(a_string_including('Quero um agente de suporte'))
    end
  end
end
