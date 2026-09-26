require 'rails_helper'

# Registro de eventos da Prospecção (#732 item 13, ENRIQ-60): uma linha de log do Rails por evento, prefixo fixo e
# JSON, sem tabela e sem dado pessoal.
RSpec.describe Autonomia::Prospecting::EventLog do
  let(:account) { create(:account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/log', name: 'Clinica Log',
                                         phone: '+5541999990000', enriched_email: 'dono@clinica.example.com')
  end
  let(:output) { StringIO.new }

  before { allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output)) }

  def logged_events
    output.string.lines.filter_map do |line|
      next unless line.start_with?(described_class::PREFIX)

      JSON.parse(line.delete_prefix(described_class::PREFIX).strip)
    end
  end

  it 'escreve o evento com lead, conta e motivo em JSON, depois do prefixo' do
    described_class.emit('enrichment.failed', lead: lead, reason: 'empty_result', level: :warn)

    expect(logged_events).to eq(
      [{ 'event' => 'enrichment.failed', 'lead_id' => lead.id, 'account_id' => account.id, 'reason' => 'empty_result' }]
    )
  end

  it 'de uma exceção, guarda só a classe: a mensagem pode trazer telefone, e-mail ou chave' do
    error = StandardError.new('GET https://waha.test/api?phone=+5541999990000&key=chave-secreta-123 dono@clinica.example.com')

    described_class.emit('whatsapp.failed', lead: lead, reason: error, source: :google)

    expect(logged_events.first).to include('reason' => 'StandardError', 'source' => 'google')
    expect(output.string).not_to include('5541999990000', 'dono@clinica.example.com', 'chave-secreta-123', 'waha.test')
  end

  it 'não aceita chave fora das previstas' do
    expect { described_class.emit('whatsapp.checked', lead: lead, phone: lead.phone) }.to raise_error(ArgumentError)
  end
end
