require 'rails_helper'

RSpec.describe Autonomia::Agents::Builder, 'B3 creation contract' do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }

  def base_output(overrides = {})
    {
      'name' => 'Ana', 'agent_type' => 'sdr', 'instruction' => 'Instrução da Ana.', 'scaffold' => 'andaime',
      'human_card' => 'A Ana organiza os leads.', 'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.',
      'handoff_rule' => 'Encaminhar quando necessário.', 'starter_questions' => [], 'tone' => 'cordial',
      'guardrails' => [], 'voice' => 'feminina', 'needs_more_info' => true,
      'next_question' => 'Para quem a Ana atende?', 'user_asked_to_close' => false,
      'knows' => { 'negocio' => 'A empresa vende seguros.', 'publico' => '', 'quando_chama' => '', 'nome' => '' },
      'suggested_links' => []
    }.merge(overrides)
  end

  def stub_model_output(parsed)
    fake_client = instance_double(Crm::Ai::ResponsesClient, create: { text: parsed.to_json })
    allow(builder).to receive(:client).and_return(fake_client)
  end

  it 'declares knows and suggested_links as strict structured output fields' do
    schema = described_class::BUILDER_SCHEMA.fetch(:schema)
    knows = schema.fetch(:properties).fetch(:knows)

    expect(knows).to include(type: 'object', additionalProperties: false)
    expect(knows.fetch(:properties).keys).to contain_exactly(:negocio, :publico, :quando_chama, :nome)
    expect(knows.fetch(:required)).to contain_exactly('negocio', 'publico', 'quando_chama', 'nome')
    expect(schema.fetch(:properties).fetch(:suggested_links)).to include(type: 'array')
    expect(schema.fetch(:required)).to include('knows', 'suggested_links')
  end

  it 'persists the model structured knows object and suggested links in the filtered state' do
    thread.append_message!('user', 'O negócio atende empresas e pessoas.')
    output = base_output(
      'knows' => {
        'negocio' => 'A empresa atende empresas e pessoas.', 'publico' => 'Empresas e pessoas',
        'quando_chama' => '', 'nome' => ''
      },
      'suggested_links' => ['https://example.test/servicos']
    )
    stub_model_output(output)

    builder.run!(thread.begin_build!)

    state = thread.reload.state
    expect(state.fetch('knows')).to eq(output.fetch('knows'))
    expect(state.fetch('suggested_links')).to eq(output.fetch('suggested_links'))
    expect(state.fetch('needs_more_info')).to be(true)
  end

  it 'uses only the structured model facts for out of order answers, never text matching' do
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.save!
    thread.append_message!('user', 'Meu negócio atende o público e chama a equipe pelo nome Ana.')
    output = base_output(
      'knows' => { 'negocio' => '', 'publico' => '', 'quando_chama' => '', 'nome' => 'Ana' },
      'next_question' => 'Qual é o negócio?'
    )
    stub_model_output(output)

    builder.run!(thread.begin_build!)

    expect(thread.reload.state.fetch('knows')).to eq(output.fetch('knows'))
    expect(thread.state.fetch('needs_more_info')).to be(true)
    expect(thread.state.fetch('next_question')).to eq('Qual é o negócio?')
  end

  it 'closes deterministically after the four knows values even when the model asks one more question' do
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.save!
    thread.append_message!('user', 'Já respondi tudo, pode montar.')
    thread.update!(state: thread.state.to_h.merge('force_close' => true))
    output = base_output(
      'needs_more_info' => true,
      'next_question' => 'Ainda falta algum detalhe?',
      'user_asked_to_close' => false,
      'knows' => {
        'negocio' => 'A empresa vende seguros.', 'publico' => 'Famílias.',
        'quando_chama' => 'Quando faltar informação.', 'nome' => 'Ana'
      }
    )
    stub_model_output(output)

    builder.run!(thread.begin_build!)

    reloaded = thread.reload
    expect(reloaded.state.fetch('knows')).to eq(output.fetch('knows'))
    expect(reloaded.state.fetch('needs_more_info')).to be(false)
    expect(reloaded.state.fetch('next_question')).to eq('')
    expect(reloaded.state.fetch('applied')).to be(true)
    expect(reloaded.agent.instruction).to be_present
  end

  it 'keeps the name as the last unanswered structured item' do
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.save!
    thread.append_message!('user', 'O negócio atende lojas e encaminha casos complexos.')
    output = base_output(
      'next_question' => 'Como você quer chamar este agente?',
      'knows' => {
        'negocio' => 'A empresa atende lojas.', 'publico' => 'Lojistas',
        'quando_chama' => 'Em casos complexos.', 'nome' => ''
      }
    )
    stub_model_output(output)

    builder.run!(thread.begin_build!)

    expect(thread.reload.state.fetch('knows')).to include('nome' => '')
    expect(thread.state.fetch('next_question')).to eq('Como você quer chamar este agente?')
    expect(thread.state.fetch('needs_more_info')).to be(true)
  end
end
