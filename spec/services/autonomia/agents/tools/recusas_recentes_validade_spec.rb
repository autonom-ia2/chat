require 'rails_helper'

# #2154: a validade da lista de recusas é lida ANTES de escrever. Nunca encurta a que o aviso do agente estendeu, e se a
# leitura falhar a lista ainda ganha a validade padrão (nunca fica sem expirar).
RSpec.describe Autonomia::Agents::Tools::RecusasRecentes do
  let(:conversa) { 876_543 }
  let(:chave) { format(described_class::CHAVE, conversa: conversa) }

  before { Redis::Alfred.delete(chave) }

  it 'lista nova ganha a validade padrão' do
    described_class.anotar(conversa, 'especialista_falhou')

    expect(Redis::Alfred.ttl(chave)).to be_within(5).of(described_class::VALIDADE.to_i)
  end

  it 'não encurta a validade estendida até a passagem' do
    described_class.anotar(conversa, 'especialista_falhou')
    described_class.guardar_ate_a_passagem(conversa)

    described_class.anotar(conversa, 'especialista_falhou')

    expect(Redis::Alfred.ttl(chave)).to be > described_class::VALIDADE.to_i
  end

  it 'a leitura da validade falhou: a lista ainda expira, com a validade padrão', :aggregate_failures do
    allow(Redis::Alfred).to receive(:ttl).and_raise(Redis::CannotConnectError)

    described_class.anotar(conversa, 'especialista_falhou')

    expect(Redis::Alfred.lrange(chave, 0, -1)).to eq(['especialista_falhou'])
    allow(Redis::Alfred).to receive(:ttl).and_call_original
    expect(Redis::Alfred.ttl(chave)).to be_within(5).of(described_class::VALIDADE.to_i)
  end
end
