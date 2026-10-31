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
      expect(Autonomia::Agents::Tool::TEMPO_PADRAO).to eq(10)
      expect(opcoes_do_fetch).to include(total_timeout: 10, open_timeout: 2, read_timeout: 8)
    end

    it 'waits the time chosen for the tool' do
      tool.update!(timeout_seconds: 45)

      expect(opcoes_do_fetch).to include(total_timeout: 45, open_timeout: 2, read_timeout: 43)
    end

    # Decisão do Rodrigo (31/10, "9. B tirar"): sem máximo nosso. Só zero, negativo ou vazio são recusados (defeito).
    it 'refuses only zero, negative or empty times, with no maximum' do
      [0, -1, nil, 1.5].each do |segundos|
        tool.timeout_seconds = segundos
        expect(tool).not_to be_valid, segundos.inspect
      end
      [1, 10, 60, 600, 3600].each do |segundos|
        tool.timeout_seconds = segundos
        expect(tool).to be_valid, segundos.inspect
      end
    end

    it 'waits a long time when the tool asks for it' do
      tool.update!(timeout_seconds: 600)

      expect(opcoes_do_fetch).to include(total_timeout: 600, read_timeout: 598)
    end

    # Pula a validação de propósito: é o CHECK do banco que está sob teste.
    it 'keeps zero out of the database too' do
      expect { tool.update_column(:timeout_seconds, 600) }.not_to raise_error # rubocop:disable Rails/SkipsModelValidations
      expect { tool.update_column(:timeout_seconds, 0) }.to raise_error(ActiveRecord::StatementInvalid) { |erro| # rubocop:disable Rails/SkipsModelValidations
        expect(erro.message).to include('autonomia_agent_tools_timeout_seconds')
      }
    end

    it 'takes the default from a single constant, for new tools' do
      stub_const('Autonomia::Agents::Tool::TEMPO_PADRAO', 30)

      expect(Autonomia::Agents::Tool.new.timeout_seconds).to eq(30)
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

    # Decisão (A) do Rodrigo: "1 T42" e depois "mais um igual" no mesmo turno são DOIS pedidos. A chave leva o número
    # da ocorrência da chamada idêntica no turno (1ª = 0, 2ª = 1); refazer o turno conta de novo do zero.
    it 'sends two keys for the same call made twice in one turn, and the same two when the turn is redone' do
      primeira_passada = turno
      chamar(primeira_passada, call_id: 'call_1')
      chamar(primeira_passada, '{"sku":"T99","qtd":3}', call_id: 'call_2')
      chamar(primeira_passada, call_id: 'call_3')
      refeita = turno
      chamar(refeita, call_id: 'call_4')
      chamar(refeita, call_id: 'call_5')

      expect(enviados.size).to eq(5)
      expect(chave_enviada(0)).not_to eq(chave_enviada(2))
      expect([chave_enviada(3), chave_enviada(4)]).to eq([chave_enviada(0), chave_enviada(2)])
    end

    # Repetir depois de uma falha é a MESMA tentativa, não "mais um igual": sem resposta 2xx o número não avança. Sem isso,
    # o dono gravaria o pedido no tempo esgotado (que chegou lá) e de novo na repetição, com outra chave.
    it 'keeps the key when the same call is repeated after a timeout or an error, in the turn and when it is redone' do
      tentativas = 0
      stub_request(:post, endpoint).to_return do |request|
        enviados << request
        tentativas += 1
        raise Net::ReadTimeout if tentativas == 1

        { status: tentativas == 2 ? 503 : 200, body: '{"ok":true}', headers: { 'Content-Type' => 'application/json' } }
      end
      passada = turno
      3.times { |indice| chamar(passada, call_id: "call_#{indice}") }
      chamar(turno, call_id: 'retry')

      expect(enviados.size).to eq(4)
      expect(enviados.map { |pedido| pedido.headers['Idempotency-Key'] }.uniq.size).to eq(1)
    end

    it 'does not spend the number on a call refused before it leaves' do
      passada = turno
      recusou = false
      allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, *args, **opcoes, &bloco|
        unless recusou
          recusou = true
          raise SafeFetch::UnsafeUrlError, 'dns'
        end

        original.call(*args, **opcoes, &bloco)
      end
      chamar(passada, call_id: 'recusada')
      chamar(passada, call_id: 'repetida')
      chamar(turno, call_id: 'retry')

      expect(enviados.size).to eq(2)
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

    # No retry o modelo escreve os argumentos de novo e pode mudar o tipo; o corpo enviado é o mesmo.
    it 'sends the same key when the redone turn writes a number as text' do
      chamar(turno, '{"sku":"T42","qtd":1}')
      chamar(turno, '{"sku":"T42","qtd":"1"}')

      expect(enviados.map(&:body).uniq.size).to eq(1)
      expect(chave_enviada(0)).to eq(chave_enviada(1))
    end

    # O ajudante (tema 14) roda a ferramenta sem `delivery`; a chave vem do turno do principal.
    it 'sends the same key when a helper agent redoes the call in the same turn' do
      bound = Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool)
      call = { 'name' => tool.slug, 'arguments' => '{"sku":"T42","qtd":1}', 'call_id' => 'c' }
      2.times { Autonomia::Agents::Specialists::LacoDoAjudante.new(vinculo: nil, delivery: turno).executar(bound, call) }

      expect(enviados.size).to eq(2)
      expect(chave_enviada(0)).to eq(chave_enviada(1))
    end

    # O ajudante e o principal dividem o turno: o mesmo pedido feito pelos dois, um depois do outro, é "mais um igual".
    it 'counts the calls of the main agent and of the helper together' do
      passada = turno
      chamar(passada, call_id: 'principal')
      bound = Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool)
      call = { 'name' => tool.slug, 'arguments' => '{"sku":"T42","qtd":1}', 'call_id' => 'ajudante' }
      Autonomia::Agents::Specialists::LacoDoAjudante.new(vinculo: nil, delivery: passada).executar(bound, call)

      expect(enviados.size).to eq(2)
      expect(chave_enviada(0)).not_to eq(chave_enviada(1))
    end

    it 'sends different keys for two tools in the same turn' do
      outra = tool.dup.tap { |copia| copia.update!(name: 'Outro', slug: 'outro_pedido') }

      expect(chave.para(tool: tool, turno: turno, params: { 'sku' => 'T42' }))
        .not_to eq(chave.para(tool: outra, turno: turno, params: { 'sku' => 'T42' }))
    end

    it 'refuses a tool that configures its own Idempotency-Key header, in any case' do
      %w[Idempotency-Key idempotency-key].each do |nome|
        tool.headers_config = [{ key: nome, value: 'fixa', secret: false }]

        expect(tool).not_to be_valid, nome
        expect(tool.errors[:headers_config].join).to include('Idempotency-Key')
      end
    end

    it 'sends a fresh key on each call without a turn (test button)' do
      2.times { Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: { sku: 'T42', qtd: 1 }).call }

      expect(chave_enviada(0)).to be_present
      expect(chave_enviada(0)).not_to eq(chave_enviada(1))
    end

    it 'is a keyed digest, without the arguments or the conversation in clear text' do
      chamar(turno, '{"sku":"SEGREDO-T42","qtd":1}')

      expect(chave_enviada.length).to eq(64)
      expect(chave_enviada.delete('0-9a-f')).to be_empty
      sem_segredo = OpenSSL::Digest::SHA256.hexdigest(JSON.generate([account.id, conversation.id, turno.turno, tool.id,
                                                                     { 'qtd' => 1, 'sku' => 'SEGREDO-T42' }]))
      expect(chave_enviada).not_to eq(sem_segredo)
    end
  end
end
