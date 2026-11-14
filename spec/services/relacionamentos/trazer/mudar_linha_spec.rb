require 'rails_helper'

# #2896 — o conserto de uma linha de "Trazer minha lista". O contrato da rota está em
# spec/requests/api/v1/accounts/relacionamentos_trazer_linhas_spec.rb; aqui, o que não dá para mandar por ela.
RSpec.describe Relacionamentos::Trazer::MudarLinha, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  def lida(texto)
    importacao = create_contact_import(account: account, user: user, content: texto)
    importacao.update!(options: importacao.options.merge('trazer' => {}))
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  # M7: um caractere de controle no valor quebraria o fechamento da conferência, sempre do mesmo jeito.
  it 'tira os caracteres de controle do valor, o byte nulo inclusive, antes de conferir' do
    importacao = lida("Nome;Celular\n;11987650001\nBruno Brandolim;11987650002\n")

    resultado = described_class.new(importacao, 2).consertar(valor: "Ana\u0000 Albu\u0007querino\n")

    expect(resultado.problema).to include(estado: 'guardado', corrigido: 'Ana Albuquerino')
    expect(ContactImports::Trazer::Consertos.new(importacao.reload).ler[2]['valores']).to eq('name' => 'Ana Albuquerino')
  end
end
