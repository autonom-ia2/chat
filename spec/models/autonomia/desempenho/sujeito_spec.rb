require 'rails_helper'

# As tabelas da leitura do painel de desempenho (#2251): validações e o que acontece quando a conversa sai.
RSpec.describe Autonomia::Desempenho::Sujeito do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }

  it 'recusa sujeito fora de agente/robô, ficha sem objeto e versão repetida' do
    ficha = ficha_da_loja!(account, sujeito_id: 7)

    expect(Autonomia::Desempenho::Ficha.new(ficha.attributes.except('id').merge('sujeito_type' => 'AgentBot'))).not_to be_valid
    repetida = Autonomia::Desempenho::Ficha.new(ficha.attributes.except('id'))
    expect(repetida).not_to be_valid
    expect(repetida.errors.attribute_names).to include(:versao)
    expect(Autonomia::Desempenho::Ficha.new(ficha.attributes.except('id').merge('versao' => 2, 'catalogo' => []))).not_to be_valid
  end

  it 'recusa procura de conversa de outra conta, ordem repetida e fim antes do início' do
    procura = procura_da_loja!(conversa, sujeito_id: 7, inicio: '2026-10-20 10:00')
    copia = procura.attributes.except('id')

    expect(Autonomia::Desempenho::Procura.new(copia)).not_to be_valid
    expect(Autonomia::Desempenho::Procura.new(copia.merge('ordem' => 2, 'fim_em' => procura.inicio_em - 1.minute))).not_to be_valid
    estranha = create(:conversation)
    expect(Autonomia::Desempenho::Procura.new(copia.merge('ordem' => 2, 'conversation_id' => estranha.id))).not_to be_valid
  end

  it 'aceita só os estados de leitura e os períodos conhecidos' do
    leitura = leitura_da_loja!(conversa, sujeito_id: 7, ate: '2026-10-22 18:00')

    expect(leitura.tap { |l| l.status = 'pela_metade' }).not_to be_valid
    recomendacao = Autonomia::Desempenho::Recomendacao.new(account: account, sujeito_type: 'robo', sujeito_id: 7, periodo: '15',
                                                           inicio: Date.current, fim: Date.current, versao_ficha: 1, cartoes: [],
                                                           gerada_em: Time.current, lote: 'spec')
    expect(recomendacao).not_to be_valid
    expect(recomendacao.tap { |r| r.periodo = '7' }).to be_valid
  end

  it 'apaga a leitura e as procuras quando a conversa é apagada' do
    procura_da_loja!(conversa, sujeito_id: 7, inicio: '2026-10-20 10:00')
    leitura_da_loja!(conversa, sujeito_id: 7, ate: '2026-10-22 18:00')

    conversa.destroy!

    expect(Autonomia::Desempenho::Procura.where(account_id: account.id)).to be_empty
    expect(Autonomia::Desempenho::Leitura.where(account_id: account.id)).to be_empty
  end
end
