require 'rails_helper'

# #1430 — tempo de espera por ferramenta (10 a 60 s, padrão 10) e `Idempotency-Key` em toda chamada.
# A chave é estável no turno: refazer o turno (retry do ReplyJob, que pede a ferramenta de novo ao
# modelo com outro `call_id`) manda a MESMA chave, e o sistema do dono não grava o pedido duas vezes.
RSpec.describe Autonomia::Agents::Tools::ChaveDeIdempotencia do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:outra_conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:endpoint) { 'https://api.loja.test/pedidos' }
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Pedido', slug: 'criar_pedido', endpoint_url: endpoint,
      request_body_template: '{"sku":"{{sku}}","qtd":{{qtd}}}',
      param_schema: [{ name: 'sku', type: 'string', description: 'SKU' }, { name: 'qtd', type: 'integer', description: 'Qtd' }]
    )
  end
  let(:enviados) { [] }
  let(:chave) { described_class }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.loja.test').and_return(['93.184.216.34'])
    stub_request(:post, endpoint).to_return do |request|
      enviados << request
      { status: 200, body: '{"ok":true}', headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def turno(conversa = conversation, mensagem: 77)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: agent_inbox, origin_message_id: mensagem)
  end

  def chamar(delivery, argumentos = '{"sku":"T42","qtd":1}', call_id: 'call_1')
    Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool)
                                   .execute({ 'name' => tool.slug, 'arguments' => argumentos, 'call_id' => call_id }, delivery: delivery)
  end

  def chave_enviada(indice = -1)
    enviados[indice].headers['Idempotency-Key']
  end

  describe 'tempo de espera' do
    def opcoes_do_fetch
      allow(SafeFetch).to receive(:fetch)
      Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: { sku: 'T42', qtd: 1 }).call
      opcoes = nil
      expect(SafeFetch).to have_received(:fetch) { |_url, **kwargs| opcoes = kwargs }
      opcoes
    end

    it 'waits 10 s in total by default, as before' do
      expect(opcoes_do_fetch).to include(total_timeout: 10, open_timeout: 2, read_timeout: 8)
    end

    it 'waits the time chosen for the tool' do
      tool.update!(timeout_seconds: 45)

      expect(opcoes_do_fetch).to include(total_timeout: 45, open_timeout: 2, read_timeout: 43)
    end

    it 'accepts only 10 to 60 seconds' do
      [9, 61, nil].each do |segundos|
        tool.timeout_seconds = segundos
        expect(tool).not_to be_valid, segundos.inspect
      end
      [10, 60].each do |segundos|
        tool.timeout_seconds = segundos
        expect(tool).to be_valid, segundos.inspect
      end
    end
  end

  describe 'Idempotency-Key' do
    it 'sends the same key when the turn is redone, even with another call id' do
      chamar(turno, call_id: 'call_1')
      chamar(turno, call_id: 'call_2')

      expect(enviados.size).to eq(2)
      expect(chave_enviada(0)).to be_present
      expect(chave_enviada(0)).to eq(chave_enviada(1))
    end

    it 'sends different keys for two conversations with the same arguments' do
      chamar(turno(conversation))
      chamar(turno(outra_conversa))

      expect(chave_enviada(0)).not_to eq(chave_enviada(1))
    end

    it 'sends a different key for a new message of the customer' do
      chamar(turno(mensagem: 77))
      chamar(turno(mensagem: 78))

      expect(chave_enviada(0)).not_to eq(chave_enviada(1))
    end

    it 'does not depend on the order of the arguments, but on their values' do
      chamar(turno, '{"sku":"T42","qtd":1}')
      chamar(turno, '{"qtd":1,"sku":"T42"}')
      chamar(turno, '{"sku":"T42","qtd":2}')

      expect(chave_enviada(0)).to eq(chave_enviada(1))
      expect(chave_enviada(0)).not_to eq(chave_enviada(2))
    end

    it 'sends different keys for two tools in the same turn' do
      outra = tool.dup.tap { |copia| copia.update!(name: 'Outro', slug: 'outro_pedido') }

      expect(chave.para(tool: tool, delivery: turno, params: { 'sku' => 'T42' }))
        .not_to eq(chave.para(tool: outra, delivery: turno, params: { 'sku' => 'T42' }))
    end

    it 'keeps the key of the platform when the tool configures its own Idempotency-Key header' do
      tool.update!(headers_config: [{ key: 'Idempotency-Key', value: 'fixa', secret: false }])

      chamar(turno)

      expect(chave_enviada).not_to eq('fixa')
      expect(chave_enviada).to eq(chave.para(tool: tool, delivery: turno, params: { 'sku' => 'T42', 'qtd' => 1 }))
    end

    it 'sends a fresh key on each call without a turn (test button)' do
      2.times { Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: { sku: 'T42', qtd: 1 }).call }

      expect(chave_enviada(0)).to be_present
      expect(chave_enviada(0)).not_to eq(chave_enviada(1))
    end

    it 'is a digest, without the arguments or the conversation in clear text' do
      chamar(turno, '{"sku":"SEGREDO-T42","qtd":1}')

      expect(chave_enviada.length).to eq(64)
      expect(chave_enviada.delete('0-9a-f')).to be_empty
    end
  end
end
