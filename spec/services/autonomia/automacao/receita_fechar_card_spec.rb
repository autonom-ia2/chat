require 'rails_helper'

# G25 (#2650): fechar o card só como ganho ou perdido. Reabrir desfaz um desfecho sem ninguém olhando, e o `force` do
# restaurar não é da automação: a Receita recusa ao salvar, com a frase.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }

  def problemas(corpo)
    passo = { 'id' => 'f1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/close', 'descricao' => 'Fechar o card',
              'caminho' => { 'id' => 7 }, 'corpo' => corpo }
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
    described_class.new(receita, conta: account, account_user: nil).problemas
  end

  def fora = I18n.t('autonomia.automacao.receita.um_de', passo: 'f1', campo: 'result', opcoes: 'won, lost')

  it 'aceita ganho e perdido, o perdido com motivo', :aggregate_failures do
    expect(problemas('result' => 'won')).to be_empty
    expect(problemas('result' => 'lost', 'lost_reason' => 'Preço')).to be_empty
  end

  it 'recusa reabrir, o alias da tela e o fechamento sem resultado', :aggregate_failures do
    expect(problemas('result' => 'reopen')).to include(fora)
    expect(problemas('result' => 'open')).to include(fora)
    expect(problemas('lost_reason' => 'Preço')).to include(fora)
  end

  it 'recusa o force' do
    expect(problemas('result' => 'won', 'force' => true))
      .to include(I18n.t('autonomia.automacao.receita.proibido', passo: 'f1', campo: 'force'))
  end
end
