require 'rails_helper'

# A LIA (Agente de Cotação, `insurance_quote`) NÃO MUDA com o agente contratado (#3211, R1): a instrução, as
# ferramentas, as rodadas e os predicados dela seguem os do Builder, e o agente comum segue sem instrução mantida.
RSpec.describe Autonomia::Agents::Agent do
  let(:account) { create(:account) }
  let(:lia) { Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Corretora Exemplo').call }

  it 'instrução da Lia é exatamente a do Builder' do
    expect(lia.instrucao_do_sistema).to eq(Autonomia::Insurance::QuoteAgent::Builder.instrucao_do_principal(lia))
  end

  it 'ferramentas da Lia são exatamente as do Builder' do
    expect(lia.ferramentas_nativas).to eq(Autonomia::Insurance::QuoteAgent::Builder.ferramentas_mantidas(lia))
  end

  it 'predicados e rodadas da Lia não mudam' do
    expect(lia.instrucao_mantida?).to be(true)
    expect(lia.contratado?).to be(false)
    expect(Autonomia::Agents::RodadasDoTurno.para(lia)).to eq(Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(lia))
  end

  it 'agente comum continua sem instrução mantida' do
    comum = described_class.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'instrução da Ana')
    expect(comum.instrucao_mantida?).to be(false)
    expect(comum.instrucao_do_sistema).to eq('instrução da Ana')
  end
end
