require 'rails_helper'

# A FRONTEIRA DE SAÍDA DA COTAÇÃO (entrega das frases do especialista, 12/09/2026).
#
# P1-2 — a peneira do `Progress` devolvia nil para a entrega de arquivo, e `PDF_SENT_KEY` já estava gravada: o
# comparativo nunca mais saía. Os exemplos do lote de preço (P1-1 e o token do preço) saíram com o lote, na fatia 3
# do #420: a cotação não publica mais preço.
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
  let(:params) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'vehicle' => { 'plate' => 'TYV8I74' } } }
  let(:tool) { described_class.new(agent: agent, params: params, run: run) }
  let(:progress) { Autonomia::Agents::Tools::Progress }
  let(:publicada) { Autonomia::Agents::Tools::EntregaPublicada }
  let(:connector) do
    instance_double(Autonomia::Insurance::Connector::Mock,
                    quote_validate: { 'valido' => true, 'problemas' => [] },
                    vehicle_lookup: { 'plate' => 'TYV8I74', 'model' => 'Gol', 'model_year' => 2016, 'vehicle_type' => 'v' })
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def offer(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def resultado(status, offers)
    { 'quote_id' => 'abc:1', 'status' => status, 'offers' => offers }
  end

  def poll(offers, handle: { 'quote_id' => 'abc:1' }, status: 'running')
    allow(connector).to receive(:quote_result).and_return(resultado(status, offers))
    tool.poll(handle: handle, attempt: 1)
  end

  describe 'P1-2 — o comparativo que não sai não pode ficar marcado como enviado' do
    before do
      allow(connector).to receive(:quote_proposal).and_return({ 'url' => 'https://arquivos.exemplo.test/c-9.pdf' })
    end

    def fechar(handle)
      poll([offer('43', 'Ezze', 2050.40)], handle: handle, status: 'completed')
    end

    # DESDE A RODADA 2 DA FATIA 1 DO PDF RÁPIDO a emissão grava só a identidade do comparativo: a
    # sentinela de enviado espera o publicador assumir a entrega (o download acontece depois da passada).
    it 'grava a identidade do comparativo quando a entrega existe, e nao a sentinela de enviado' do
      resultado = fechar({ 'quote_id' => 'abc:1' })

      expect(resultado.handle[described_class::PDF_SENT_KEY]).to be_blank
      expect(resultado.handle[described_class::COMPARATIVO_KEY]).to be_present
    end

    it 'nao marca quando a entrega de arquivo nao sobrevive a fronteira' do
      # Arrange — a fronteira recusa a entrega de ARQUIVO, e só ela
      allow(progress).to receive(:entregavel).and_wrap_original do |original, valor|
        valor.is_a?(Hash) ? nil : original.call(valor)
      end

      # Act
      resultado = fechar({ 'quote_id' => 'abc:1' })

      # Assert — sem a sentinela, a passada seguinte gera o comparativo de novo
      expect(resultado.handle[described_class::PDF_SENT_KEY]).to be_blank
      expect(resultado.handle[described_class::COMPARATIVO_KEY]).to be_blank
      expect(resultado.deliveries).to be_empty
    end

    # A IDENTIDADE DO COMPARATIVO É DA ENTREGA QUE SAI, não da que se pretendia mandar. Quando a URL
    # não cabe na forma de arquivo, o que sai é o texto de reserva — e é o texto DEPURADO dele que o
    # publicador vai carimbar.
    it 'a identidade do comparativo e a da entrega depurada' do
      resultado = fechar({ 'quote_id' => 'abc:1' })

      expect(resultado.handle[described_class::COMPARATIVO_KEY])
        .to eq(publicada.token_de(run, resultado.deliveries.last))
    end
  end

  # A EXECUÇÃO ABERTA ANTES DA PR C traz o nó `frases_ao_cliente` nos argumentos. Ele não é lido por ninguém: o
  # comparativo sai sem legenda, a recusa vira evento sem texto, e nada que o especialista escreveu ali chega ao
  # cliente pelo motor.
  describe 'a execucao antiga, com as frases do especialista nos argumentos' do
    let(:params) do
      super().merge('frases_ao_cliente' => { 'comparativo_legenda' => 'Aqui está o comparativo completo.',
                                             'sem_veiculo' => 'Me manda a placa do carro, por favor.',
                                             'ramo_desconhecido' => 'Esse eu não coto por aqui.' })
    end

    it 'o comparativo sai sem a legenda que o especialista escreveu' do
      allow(connector).to receive(:quote_proposal).and_return({ 'url' => 'https://arquivos.exemplo.test/c-9.pdf' })

      entrega = poll([offer('43', 'Ezze', 2050.40)], status: 'completed').deliveries.sole

      expect(entrega.to_s).not_to include('Aqui está o comparativo completo.')
      expect(entrega['arquivo'].keys).to eq(%w[url nome])
    end

    it 'a recusa sem veiculo vira o motivo, sem a frase do especialista' do
      sem_placa = described_class.new(agent: agent, params: params.merge('vehicle' => {}), run: run)

      expect(sem_placa.start).to include('recusa' => 'sem_veiculo')
      expect(sem_placa.start.to_s).not_to include('Me manda a placa')
    end

    it 'a recusa de ramo desconhecido vira o motivo, e a lista de ramos fica nos fatos do modelo' do
      allow(connector).to receive(:quote_validate).and_raise(Autonomia::Insurance::Connector::Error.new(:not_implemented, 'sem ramo'))
      handle = described_class.new(agent: agent, params: params.merge('produto' => 'nautico'), run: run).start

      expect(handle).to include('recusa' => 'ramo_desconhecido')
      expect(handle.to_s).not_to include('Esse eu não coto')
      expect(described_class.fatos_do_evento('ramo_desconhecido', Autonomia::Agents::ToolRun.new(handle: handle))).to include('bicicleta')
    end
  end
end
