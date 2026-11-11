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

  # O valor calculado no resultado poderia reabrir o card (conversa.status "open"): o salvar recusa.
  it 'recusa o resultado calculado' do
    expect(problemas('result' => { '$valor' => 'conversa.status' })).to include(fora)
  end

  it 'recusa o force' do
    expect(problemas('result' => 'won', 'force' => true))
      .to include(I18n.t('autonomia.automacao.receita.proibido', passo: 'f1', campo: 'force'))
  end

  # Decisão 19 (09/11): o card da conversa (#2716) é só para ler. O fechar o card, que leva `card.id` no caminho, fica
  # fora do gatilho de conversa, também dentro de um ramo; no gatilho de card, entra.
  describe 'o card da conversa não fecha' do
    def fechar_pelo_card(id = 'f1')
      { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/close', 'descricao' => 'Fechar o card',
        'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'result' => 'won' } }
    end

    def problemas_no(gatilho, *passos)
      receita = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => passos }
      described_class.new(receita, conta: account, account_user: nil).problemas
    end

    def so_le(passo) = I18n.t('autonomia.automacao.receita.card_da_conversa_so_le', passo: passo, caminho: 'card.id')

    it 'recusa no gatilho de conversa, no passo e no ramo', :aggregate_failures do
      condicao = { 'campo' => { '$valor' => 'conversa.status' }, 'op' => 'igual', 'valor' => 'resolved' }
      ramo = { 'id' => 's1', 'tipo' => 'se', 'condicao' => condicao, 'entao' => [fechar_pelo_card('f2')], 'senao' => [] }

      expect(problemas_no('conversa.resolvida', fechar_pelo_card)).to include(so_le('f1'))
      expect(problemas_no('conversa.resolvida', ramo)).to include(so_le('f2'))
    end

    it 'aceita no gatilho de card' do
      expect(problemas_no('card.ganho', fechar_pelo_card)).not_to include(so_le('f1'))
    end
  end
end
