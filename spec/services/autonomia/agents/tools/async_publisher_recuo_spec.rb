require 'rails_helper'

# O TEXTO DE RESERVA QUE SAI FICA NO LOG (fatia 3 do #420): cada mensagem nova da cotação que leva um recuo é
# registrada com a execução e o papel. A frase escrita pelo especialista não é registrada.
RSpec.describe Autonomia::Agents::Tools::AsyncPublisher do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, arguments: {},
                                     scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
                              .tap { |linha| linha.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now) }
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { allow(Rails.logger).to receive(:warn) }

  it 'o recuo publicado sai no log com a execucao e o papel' do
    resultado = described_class.new(run: run).publish!(cotacao::Declaracao::FALHOU)

    expect(resultado).to be_published
    expect(Rails.logger).to have_received(:warn).with("[autonomia][recuo] run=#{run.id} slug=#{cotacao.slug} papel=falhou")
  end

  it 'o pedido do que falta com a lista depois do recuo tambem sai no log' do
    described_class.new(run: run).publish!("#{cotacao::Recusas::PEDIDO_DO_QUE_FALTA}\n- a placa")

    expect(Rails.logger).to have_received(:warn).with(/\[autonomia\]\[recuo\] run=#{run.id} .* papel=pedido_do_que_falta/)
  end

  it 'a frase escrita pelo especialista nao e registrada como recuo' do
    described_class.new(run: run).publish!('Não deu para fechar agora, alguém da equipe continua com você.')

    expect(Rails.logger).not_to have_received(:warn).with(/\[autonomia\]\[recuo\]/)
  end

  it 'a republicacao do mesmo texto nao registra de novo' do
    2.times { described_class.new(run: run).publish!(cotacao::Declaracao::FALHOU) }

    expect(Rails.logger).to have_received(:warn).with(/\[autonomia\]\[recuo\]/).once
  end
end
