require 'rails_helper'

# #2896 — as respostas da conferência de "Trazer minha lista". O contrato da rota está em
# spec/requests/api/v1/accounts/relacionamentos_trazer_respostas_spec.rb; aqui, o que não dá para ver por ela.
RSpec.describe Relacionamentos::Trazer::Responder, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:planilha) { "Nome;Celular;E-mail;Cliente?\nAna Albuquerino;11987650001;ana@exemplo.com.br;sim\n" }

  def lida(texto = planilha)
    importacao = create_contact_import(account: account, user: user, content: texto)
    importacao.update!(options: importacao.options.merge('trazer' => {}))
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  def responder(importacao, **respostas)
    described_class.new(importacao, respostas.stringify_keys).call
  end

  it 'não há pergunta de telefone quando o sistema achou a coluna com certeza: a resposta é recusada' do
    enable_audience_jev
    stub_audience_jev(phone: 'column_1', email: 'column_2', name: 'column_0', company: 'none')
    importacao = lida

    expect(Relacionamentos::Trazer::Perguntas.new(importacao).call).to eq([{ id: 'clientes' }])
    expect(responder(importacao, telefone: 'da_empresa')).to have_attributes(erro: 'pergunta_desconhecida', revalida: nil)
    expect(importacao.reload.options['trazer']).to eq({})
  end

  it 'a pergunta do telefone continua na lista depois de respondida, enquanto a coluna está onde a resposta a pôs' do
    account.enable_features!('companies')
    importacao = lida("Nome;Celular;E-mail;Empresa\nAna Albuquerino;11987650001;ana@exemplo.com.br;Padaria Bom Dia\n")

    expect(responder(importacao, telefone: 'da_empresa')).to have_attributes(erro: nil, revalida: true)
    ContactImports::Validator.new(importacao).perform
    importacao.reload

    expect(importacao.schema_resolution.dig('targets', 'phone', 'column')).to be_nil
    expect(Relacionamentos::Trazer::Perguntas.new(importacao).telefone).to eq(id: 'telefone', coluna: 'Celular', indice: 1)
    expect(importacao.options['trazer']['respostas']).to eq('telefone' => 'da_empresa', 'coluna_telefone' => 1)

    # A pessoa manda a coluna para outro lugar pela tela das colunas: a resposta antiga deixa de valer.
    Relacionamentos::Trazer::TrocarDestino.new(importacao, indice: 1, destino: 'cidade').call
    perguntas = Relacionamentos::Trazer::Perguntas.new(importacao.reload)
    expect(perguntas.telefone).to be_nil
    expect(perguntas.respostas_da_tela).to eq({})
  end

  it 'desfaz o que o pedido já tinha mudado quando a segunda resposta é recusada' do
    importacao = lida("Nome;Celular;Cliente?\nAna Albuquerino;11987650001;sim\n")
    importacao.update!(options: importacao.options.merge('trazer' => { 'destinos' => { '2' => 'cliente' } }))

    resultado = described_class.new(importacao, 'clientes' => 'ainda_nao', 'telefone' => 'nao_usar').call

    expect(resultado.erro).to eq('sem_contato')
    expect(importacao.reload).to be_ready_to_confirm
    expect(importacao.options['trazer']).to eq('destinos' => { '2' => 'cliente' })
  end
end
