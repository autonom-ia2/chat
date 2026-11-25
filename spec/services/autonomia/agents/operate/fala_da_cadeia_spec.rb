require 'rails_helper'

# #3211/#3218: a fala na cadeia de pedaços. E-mail fica fora da paridade, com a chave gravada ou não.
RSpec.describe Autonomia::Agents::Operate::FalaDaCadeia do
  let(:agente) { Autonomia::Agents::Agent.new(config: { 'conversa_entrega_inteira' => true, 'conversa_em_fila' => true }) }

  it 'fora do e-mail, do 2º pedaço em diante a fala já começou' do
    expect(described_class.comecada?(agente, Inbox.new, 1)).to be(true)
  end

  # Pega: o job deixar de conferir o turno no e-mail (mensagem nova não cortaria os pedaços que faltam).
  it 'caixa de e-mail, mesmo com as chaves true gravadas: a fala não começou' do
    caixa_de_email = create(:channel_email).inbox

    expect(described_class.comecada?(agente, caixa_de_email, 1)).to be(false)
  end
end
