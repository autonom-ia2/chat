require 'rails_helper'

# E6 (#2899): telefone e e-mail só da página do CPF/CNPJ do segurado. Dados fictícios.
RSpec.describe Carteira::Leitor::ContatoDoSegurado do
  let(:pagina) { Carteira::Leitor::Paginas::Pagina }
  let(:paginas) do
    [pagina.new(numero: 1, texto: "Segurado: Marina Exemplo CPF 123.456.789-00\nTel.: (11) 99999-0001  E-mail: Marina.Exemplo@\nexemplo.invalid"),
     pagina.new(numero: 3, texto: 'Corretor: (11) 3000-0002 contato@corretora-amostra.invalid. Assistência: 0800 000 0004'),
     pagina.new(numero: 9, texto: 'Anexo do segurado, CPF 123.456.789-00. Celular +55 (11) 98888-0005')]
  end
  let(:documento) { '12345678900' }

  def contato(resposta, do_documento: documento)
    described_class.new(paginas, documento: do_documento).call(resposta)
  end

  it 'aceita o telefone e o e-mail escritos numa página do documento do segurado' do
    resposta = { 'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
                 'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1 }

    expect(contato(resposta)).to eq('segurado_telefone' => '11999990001', 'segurado_email' => 'marina.exemplo@exemplo.invalid')
    expect(contato({ 'segurado_telefone' => '+55 11 98888-0005', 'segurado_telefone_pagina' => 9 })['segurado_telefone']).to eq('5511988880005')
  end

  it 'recusa o contato da página em que o documento do segurado não aparece' do
    resposta = { 'segurado_telefone' => '(11) 3000-0002', 'segurado_telefone_pagina' => 3,
                 'segurado_email' => 'contato@corretora-amostra.invalid', 'segurado_email_pagina' => 3 }

    expect(contato(resposta)).to eq('segurado_telefone' => nil, 'segurado_email' => nil)
  end

  it 'recusa o contato que não está escrito na página que o modelo indicou' do
    resposta = { 'segurado_telefone' => '(11) 3000-0002', 'segurado_telefone_pagina' => 1,
                 'segurado_email' => 'contato@corretora-amostra.invalid', 'segurado_email_pagina' => 9 }

    expect(contato(resposta)).to eq('segurado_telefone' => nil, 'segurado_email' => nil)
  end

  it 'sem o documento do segurado, ou com um que não aparece em página nenhuma, não há contato' do
    resposta = { 'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
                 'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1 }

    [nil, '', '99988877766'].each do |outro|
      expect(contato(resposta, do_documento: outro)).to eq('segurado_telefone' => nil, 'segurado_email' => nil)
    end
  end

  it 'recusa telefone com dígitos de menos ou de mais, página que não existe e valor que não é texto' do
    telefones = [['9999-0001', 1], ['0800 000 0004 0800 000', 1], ['(11) 99999-0001', 2], ['(11) 99999-0001', nil], ['(11) 99999-0001', '1'],
                 [nil, 1], [11_999_990_001, 1]]

    expect(telefones.map { |valor, numero| contato({ 'segurado_telefone' => valor, 'segurado_telefone_pagina' => numero })['segurado_telefone'] })
      .to all(be_nil)
  end

  it 'recusa e-mail sem cara de e-mail, mesmo escrito na página' do
    emails = ['marina.exemplo@', '@exemplo.invalid', 'marina.exemplo@exemplo', 'marina exemplo@exemplo.invalid', 'a@b@exemplo.invalid',
              'marina.exemplo@.invalid', nil, 42]

    expect(emails.map { |valor| contato({ 'segurado_email' => valor, 'segurado_email_pagina' => 1 })['segurado_email'] }).to all(be_nil)
  end
end
