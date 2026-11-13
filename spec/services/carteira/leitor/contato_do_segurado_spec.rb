require 'rails_helper'

# E6 (#2899): telefone e e-mail só da página do CPF/CNPJ do segurado, escritos por inteiro. Dados fictícios.
RSpec.describe Carteira::Leitor::ContatoDoSegurado do
  let(:pagina) { Carteira::Leitor::Paginas::Pagina }
  let(:do_segurado) do
    <<~TEXTO
      Segurado: Marina Exemplo CPF 123.456.789-00   Apólice nº 21987654321
      Tel.: (11) 99999-0001  E-mail: Marina.Exemplo@
      exemplo.invalid
      Recado: (20) 96666-0008 ou 97777-0007. Matrícula 5521 95555-0009
      CORRETOR: Corretora Amostra - (11) 3000-0002 - contato@corretora-amostra.invalid.
      Central de atendimento: 0800 000 0003 ou 4004 0010. Com DDD: (11) 4004-0011
    TEXTO
  end
  let(:paginas) do
    [pagina.new(numero: 1, texto: do_segurado),
     pagina.new(numero: 3, texto: 'Assistência: (11) 3000-0004 assistencia@exemplo.invalid. Guincho: 0800 000 0005'),
     pagina.new(numero: 9, texto: 'Anexo do segurado, CPF 123.456.789-00. Celular +55 (11) 98888-0005')]
  end
  let(:documento) { '12345678900' }

  def contato(resposta, do_documento: documento, numero: nil)
    described_class.new(paginas, documento: do_documento, numero: numero).call(resposta)
  end

  def telefone(valor, numero_da_pagina = 1, **opcoes)
    contato({ 'segurado_telefone' => valor, 'segurado_telefone_pagina' => numero_da_pagina }, **opcoes)['segurado_telefone']
  end

  def email(valor, numero_da_pagina = 1)
    contato({ 'segurado_email' => valor, 'segurado_email_pagina' => numero_da_pagina })['segurado_email']
  end

  it 'aceita o telefone e o e-mail escritos por inteiro numa página do documento do segurado' do
    resposta = { 'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
                 'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1 }

    expect(contato(resposta)).to eq('segurado_telefone' => '11999990001', 'segurado_email' => 'marina.exemplo@exemplo.invalid')
    expect(telefone('+55 11 98888-0005', 9)).to eq('5511988880005')
  end

  it 'recusa o contato da página em que o documento do segurado não aparece' do
    resposta = { 'segurado_telefone' => '(11) 3000-0004', 'segurado_telefone_pagina' => 3,
                 'segurado_email' => 'assistencia@exemplo.invalid', 'segurado_email_pagina' => 3 }

    expect(contato(resposta)).to eq('segurado_telefone' => nil, 'segurado_email' => nil)
  end

  it 'recusa o contato que não está escrito na página que o modelo indicou' do
    resposta = { 'segurado_telefone' => '(11) 3000-0004', 'segurado_telefone_pagina' => 1,
                 'segurado_email' => 'assistencia@exemplo.invalid', 'segurado_email_pagina' => 9 }

    expect(contato(resposta)).to eq('segurado_telefone' => nil, 'segurado_email' => nil)
  end

  it 'sem o documento do segurado, ou com um que não está escrito por inteiro em página nenhuma, não há contato' do
    resposta = { 'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
                 'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1 }

    # '45678900219' são os últimos dígitos do CPF emendados nos primeiros do número da apólice.
    [nil, '', '99988877766', '45678900219'].each do |outro|
      expect(contato(resposta, do_documento: outro)).to eq('segurado_telefone' => nil, 'segurado_email' => nil)
    end
  end

  # Achado D da revisão: passavam o 0800, o próprio CPF devolvido como telefone e o número com o DDD trocado.
  describe 'telefone que não é de pessoa, mesmo escrito na página do CPF' do
    it 'recusa o 0800 e o número de central' do
      expect([telefone('0800 000 0003'), telefone('4004 0010'), telefone('4004-0010')]).to all(be_nil)
    end

    it 'recusa o próprio CPF devolvido como telefone' do
      expect([telefone('123.456.789-00'), telefone('12345678900')]).to all(be_nil)
    end

    it 'recusa o número da apólice devolvido como telefone, que sem essa regra passaria' do
      expect(telefone('(21) 98765-4321', numero: '21987654321')).to be_nil
      expect(telefone('(21) 98765-4321', numero: 'EX-2026.001234')).to eq('21987654321')
    end

    it 'recusa o telefone sem DDD e o de DDD que não existe' do
      expect([telefone('97777-0007'), telefone('99999-0001'), telefone('(20) 96666-0008')]).to all(be_nil)
    end

    it 'recusa o DDD trocado: os dígitos do DDD não podem vir do fim de outro número' do
      # "5521 95555-0009" tem os dígitos 21955550009 em sequência, mas o que está escrito é 5521, não 21.
      expect([telefone('(21) 95555-0009'), telefone('(21) 99999-0001'), telefone('(11) 99999-0002')]).to all(be_nil)
    end

    it 'recusa um pedaço de número, dígitos de mais, página que não existe e valor que não é texto' do
      telefones = [['(11) 9999-0001', 1], ['(11) 99999-00010', 1], ['(11) 99999-0001', 2], ['(11) 99999-0001', nil], ['(11) 99999-0001', '1'],
                   [nil, 1], [11_999_990_001, 1]]

      expect(telefones.map { |valor, numero| telefone(valor, numero) }).to all(be_nil)
    end
  end

  # Achado E da revisão: um pedaço de e-mail passava por estar dentro de outro.
  describe 'e-mail' do
    it 'recusa o pedaço de um e-mail escrito na página' do
      pedacos = ['exemplo@exemplo.invalid', 'to@corretora-amostra.invalid', 'contato@corretora-amostra.inv', 'contato@corretora-amostra.in',
                 'marina.exemplo@exemplo.inval']

      expect(pedacos.map { |valor| email(valor) }).to all(be_nil)
    end

    it 'aceita o e-mail que a quebra de linha partiu em dois, sem contar caixa nem o ponto do fim da frase' do
      expect([email('Marina.Exemplo@exemplo.invalid'), email(' contato@corretora-amostra.invalid ')])
        .to eq(['marina.exemplo@exemplo.invalid', 'contato@corretora-amostra.invalid'])
    end

    it 'recusa e-mail sem cara de e-mail, mesmo escrito na página' do
      emails = ['marina.exemplo@', '@exemplo.invalid', 'marina.exemplo@exemplo', 'marina exemplo@exemplo.invalid', 'a@b@exemplo.invalid',
                'marina.exemplo@.invalid', nil, 42]

      expect(emails.map { |valor| email(valor) }).to all(be_nil)
    end
  end

  # O limite que fica, e por isso o contato sai do Resultado só como "a confirmar": o telefone e o e-mail do corretor
  # estão escritos por inteiro na página do CPF do segurado. Se o modelo disser que são do segurado, nenhuma
  # conferência de valor os separa. Quem mede se o modelo erra é a bateria com gabarito.
  it 'o contato do corretor na página do CPF passa na conferência de valor' do
    expect([telefone('(11) 3000-0002'), email('contato@corretora-amostra.invalid')]).to eq(['1130000002', 'contato@corretora-amostra.invalid'])
  end

  # Não há lista de prefixos: o número de central escrito com DDD tem forma de telefone fixo.
  it 'o número de central escrito com DDD também passa; sem DDD, não' do
    expect([telefone('(11) 4004-0011'), telefone('4004 0010')]).to eq(['1140040011', nil])
  end
end
