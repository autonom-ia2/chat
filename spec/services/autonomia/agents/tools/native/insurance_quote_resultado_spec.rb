require 'rails_helper'

# A COTAÇÃO GUARDA O RESULTADO POR SEGURADORA E PEDE A CONFIRMAÇÃO LOGO (fatia 2 do #420) — a ferramenta,
# montada como o motor a monta (com a linha da execução). Dados sintéticos, na forma do `Connector::Http`.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: {},
                                     scope: { conversation_id: conversation.id })
  end
  let(:params) { { 'cpf' => '111.444.777-35', 'cep' => '01001-000', 'vehicle' => { 'plate' => 'ABC1D23' } } }
  let(:tool) { described_class.new(agent: agent, params: params, run: run) }
  let(:chave) { described_class::RESULTADO_KEY }
  let(:risco) { { 'kind' => 'risco', 'text' => 'Risco sem aceitação para este cenário nesta seguradora.' } }
  let(:connector) do
    instance_double(Autonomia::Insurance::Connector::Mock,
                    quote_validate: { 'valido' => true, 'problemas' => [] },
                    quote_proposal: { 'url' => 'https://arquivos.exemplo.test/comparativo-sintetico.pdf' })
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def oferta(code, status, amount: nil, reason: nil)
    base = { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status, 'reason' => reason }.compact
    amount ? base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' }) : base
  end

  def consultar(ofertas, handle, status: 'partial')
    allow(connector).to receive(:quote_result).and_return({ 'quote_id' => 'abc:1', 'status' => status, 'offers' => ofertas })
    tool.poll(handle: handle, attempt: 5)
  end

  def inicio
    { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [] }
  end

  describe 'o resultado por seguradora no handle' do
    it 'grava em toda consulta, como união das leituras' do
      # Act — a primeira leitura lista duas; a segunda lista outras duas e dá desfecho à que corria
      primeira = consultar([oferta('8', 'quoted', amount: 2119.18), oferta('47', 'running')], inicio)
      segunda = consultar([oferta('47', 'declined', reason: risco), oferta('11', 'auth_required', reason: risco)],
                          primeira.handle)

      # Assert
      expect(primeira.handle[chave].transform_values { |e| e['desfecho'] }).to eq('8' => 'com_preco', '47' => 'aguardando')
      expect(segunda.handle[chave]).to eq(
        '8' => { 'nome' => 'Seguradora 8', 'desfecho' => 'com_preco', 'premio' => { 'amount' => 2119.18, 'basis' => 'total' } },
        '47' => { 'nome' => 'Seguradora 47', 'desfecho' => 'sem_proposta', 'motivo' => risco },
        '11' => { 'nome' => 'Seguradora 11', 'desfecho' => 'sem_proposta' }
      )
    end

    # OS CÓDIGOS DE CADA LOTE DE PREÇO (quarta rodada de revisão), sob a identidade da entrega do lote: é por eles que
    # a ferramenta da Lia sabe que preço a cotação ainda está enviando.
    it 'grava os códigos de cada lote de preço sob a identidade da entrega do lote, acumulando' do
      primeira = consultar([oferta('8', 'quoted', amount: 2119.18), oferta('47', 'running')], inicio)
      segunda = consultar([oferta('47', 'quoted', amount: 1999.0), oferta('11', 'quoted', amount: 2500.0)], primeira.handle)

      lotes = segunda.handle[described_class::LOTES_KEY]
      tokens = segunda.handle[described_class::PRECOS_KEY]
      expect(tokens.size).to eq(2)
      expect(lotes).to eq(tokens.first => ['8'], tokens.last => %w[47 11])
      expect(tokens).to eq((primeira.deliveries + segunda.deliveries).map { |texto| run.delivery_token(texto) })
    end

    it 'grava também na passada que fecha a cotação' do
      ofertas = [oferta('8', 'quoted', amount: 2119.18), oferta('47', 'declined', reason: risco)]
      handle = inicio.merge(described_class::ACIONADAS_KEY => %w[47 8], described_class::LEITURA_ASSENTADA_KEY => %w[47 8])

      progresso = consultar(ofertas, handle)

      expect(progresso).to be_done
      expect(progresso.handle[chave].keys).to contain_exactly('8', '47')
    end

    # A EXECUÇÃO EM VOO NO DEPLOY: o handle dela não tem a chave, e a primeira consulta desta versão a grava
    # com tudo o que a leitura lista, sem mexer no que o handle já tinha.
    it 'a linha em voo no deploy, sem a chave, ganha o resultado na consulta seguinte e mantém as chaves de antes' do
      legado = inicio.merge(described_class::DELIVERED_KEY => ['8'], described_class::ACIONADAS_KEY => %w[8 47])

      progresso = consultar([oferta('8', 'quoted', amount: 2119.18), oferta('47', 'running')], legado)

      expect(progresso.handle[chave].keys).to contain_exactly('8', '47')
      expect(progresso.handle[described_class::DELIVERED_KEY]).to eq(['8'])
      expect(progresso.deliveries).to be_empty
    end

    it 'não é marca do motor' do
      expect(Autonomia::Agents::Tools::AsyncRunJob::MARCAS).not_to include(chave)
    end

    it 'resultado_guardado? responde verdade só com seguradora com preço guardado' do
      com_preco = consultar([oferta('8', 'quoted', amount: 2119.18)], inicio).handle
      so_recusa = consultar([oferta('47', 'declined', reason: risco)], inicio).handle

      expect(described_class.resultado_guardado?(com_preco)).to be(true)
      expect(described_class.resultado_guardado?(so_recusa)).to be(false)
      expect(described_class.resultado_guardado?(inicio)).to be(false)
      expect(described_class.resultado_guardado?(nil)).to be(false)
    end
  end

  # A CONFIRMAÇÃO: a primeira leitura com toda seguradora com desfecho não fecha a cotação (a guarda das
  # duas leituras seguidas, fatia 1). O que esta fatia muda é só QUANDO vem a leitura seguinte.
  describe 'o pedido de confirmação logo' do
    let(:com_desfecho) { [oferta('8', 'quoted', amount: 2119.18), oferta('47', 'declined'), oferta('11', 'auth_required')] }

    it 'a primeira leitura com todas com desfecho pede a consulta seguinte logo, e não fecha' do
      progresso = consultar(com_desfecho, inicio)

      expect(progresso).to be_running
      expect(progresso.confirmar_logo?).to be(true)
      expect(progresso.handle[described_class::FECHADO_KEY]).to be_blank
    end

    it 'a leitura seguinte igual fecha a cotação' do
      primeira = consultar(com_desfecho, inicio)

      segunda = consultar(com_desfecho, primeira.handle)

      expect(segunda).to be_done
    end

    it 'não pede com seguradora ainda sem desfecho' do
      progresso = consultar(com_desfecho + [oferta('19', 'running')], inicio)

      expect(progresso).to be_running
      expect(progresso.confirmar_logo?).to be(false)
    end

    # A LEITURA IGUAL À ANTERIOR QUE NÃO FECHOU: faltou uma seguradora que outra leitura listou. A próxima
    # leitura igual também não fecharia, e a consulta volta ao intervalo da tentativa.
    it 'não pede quando a leitura repete a anterior e perdeu uma seguradora já listada' do
      handle = inicio.merge(described_class::ACIONADAS_KEY => %w[11 19 47 8], described_class::LEITURA_ASSENTADA_KEY => %w[11 47 8])

      progresso = consultar(com_desfecho, handle)

      expect(progresso).to be_running
      expect(progresso.confirmar_logo?).to be(false)
    end

    # A LEITURA ASSENTADA QUE PERDEU UMA SEGURADORA JÁ LISTADA, vinda de uma leitura em que ela corria: a
    # próxima leitura igual também não fecharia, e a consulta fica no intervalo da tentativa.
    it 'não pede quando a leitura assentada nova perdeu uma seguradora já listada' do
      handle = inicio.merge(described_class::ACIONADAS_KEY => %w[11 19 47 8])

      progresso = consultar(com_desfecho, handle)

      expect(progresso).to be_running
      expect(progresso.confirmar_logo?).to be(false)
    end

    it 'pede quando a leitura assentada é diferente da anterior e cobre as já listadas' do
      handle = inicio.merge(described_class::ACIONADAS_KEY => %w[47 8], described_class::LEITURA_ASSENTADA_KEY => %w[47 8])

      progresso = consultar(com_desfecho, handle)

      expect(progresso).to be_running
      expect(progresso.confirmar_logo?).to be(true)
    end
  end
end
