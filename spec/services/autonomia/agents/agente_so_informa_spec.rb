require 'rails_helper'

# #2154: o fim da fala que avisou pede a avaliação da IA de Atribuição e nunca derruba a entrega; a falha vai ao log e
# ao rastreador de erros do projeto.
RSpec.describe Autonomia::Agents::AgenteSoInforma do
  let(:conversation) { create(:conversation) }

  it 'pede a avaliação pelo ContratoDoFunil' do
    allow(Autonomia::Agents::ContratoDoFunil).to receive(:avaliar_depois_da_fala).and_return('agendada')

    expect(described_class.fala_terminou!(conversation)).to eq('agendada')
  end

  it 'a falha não sobe: vai ao log e ao rastreador de erros', :aggregate_failures do
    erro = RuntimeError.new('fora do ar')
    allow(Autonomia::Agents::ContratoDoFunil).to receive(:avaliar_depois_da_fala).and_raise(erro)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).with(erro, account: conversation.account).and_return(rastreador)
    allow(Rails.logger).to receive(:warn)

    expect(described_class.fala_terminou!(conversation)).to be_nil
    expect(rastreador).to have_received(:capture_exception)
    expect(Rails.logger).to have_received(:warn).with(a_string_including('aviso_de_passagem_falhou', "conv=#{conversation.id}"))
  end
end
