require 'rails_helper'

# #3106 (revisão do Codex): editar a caixa pode trocar a credencial do canal em uso. O token do Telegram refaz o
# webhook lá fora, e o desfazer devolve a coluna, não o que o provedor já trocou. Então a pessoa confirma antes.
RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:acoes) { described_class.new(account: conta, user: admin) }
  let(:caixa) { create(:inbox, account: conta) }

  it 'trocar a credencial do canal pede confirmação, por PATCH ou PUT' do
    %w[PATCH PUT].each do |verbo|
      dados = { caminho: { id: caixa.id }, corpo: { channel: { bot_token: 'novo-token' } } }

      expect(acoes.desfazivel?("#{verbo} inboxes/:id", dados)).to be(false)
    end
  end

  it 'mudar o nome da caixa segue direto, com desfazer' do
    expect(acoes.desfazivel?('PATCH inboxes/:id', { caminho: { id: caixa.id }, corpo: { name: 'Vendas' } })).to be(true)
  end

  it 'a reação ao cliente pede confirmação' do
    expect(acoes.desfazivel?('POST conversations/:conversation_id/messages/:id/reaction')).to be(false)
    expect(acoes.desfazivel?('POST conversa_canal/reacoes')).to be(false)
  end
end
