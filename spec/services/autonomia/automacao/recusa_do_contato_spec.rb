require 'rails_helper'

# O ponto único de quem não recebe nada da automação (decisão 5, #2414): a regra das campanhas (#2794).
RSpec.describe Autonomia::Automacao::RecusaDoContato do
  let(:contato) { create(:contact, account: create(:account)) }

  it 'contato normal recebe' do
    expect(described_class.motivo(contato.id)).to be_nil
  end

  it 'contato bloqueado não recebe' do
    contato.update!(blocked: true)
    expect(described_class.motivo(contato.id)).to eq('contato_bloqueado')
  end

  it 'quem pediu para não receber, mesmo bloqueado, conta como recusa (o motivo que já existia)' do
    contato.update!(blocked: true, opted_out_at: 1.day.ago)
    expect(described_class.motivo(contato.id)).to eq('contato_nao_recebe')
  end
end
