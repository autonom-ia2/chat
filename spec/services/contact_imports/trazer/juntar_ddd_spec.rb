require 'rails_helper'

# #2896 — "Trazer minha lista": o DDD que vem numa coluna separada é juntado ao número antes de a planilha ser lida. Só
# com título de DDD, ou com a coluna sem título colada à de telefone; "Idade" nunca vira DDD e o DDD que não existe não
# é juntado.
RSpec.describe ContactImports::Trazer::JuntarDdd, :aggregate_failures do
  def planilha(texto)
    CampaignImports::Parser.new(StringIO.new(texto), filename: 'lista.csv').perform
  end

  def juntar(texto)
    described_class.new(planilha(texto)).call
  end

  def tabela(resultado)
    resultado.arquivo.tables.first.rows.map(&:values)
  end

  it 'junta a coluna com título de DDD à coluna de telefone e tira a coluna do DDD' do
    resultado = juntar("Nome,DDD,Celular,Cidade\nAna,11,98765-0001,Campinas\nBia,021,987650002,Rio\nCaio,(31),8765-0003,BH\n")

    expect(resultado.juntadas).to eq(3)
    expect(tabela(resultado)).to eq(
      [%w[Nome Celular Cidade], ['Ana', '(11) 98765-0001', 'Campinas'], ['Bia', '(21) 987650002', 'Rio'], ['Caio', '(31) 8765-0003', 'BH']]
    )
    expect(resultado.arquivo.headers).to eq(%w[Nome Celular Cidade])
    expect(resultado.arquivo.rows.map(&:row_number)).to eq([2, 3, 4])
    expect(resultado.arquivo.format).to eq('csv')
  end

  it 'aceita os outros títulos de DDD e junta com a coluna de telefone mais perto, a da direita primeiro' do
    resultado = juntar("Telefone,Código de Área,WhatsApp,Nome\n33330001,11,987650001,Ana\n")

    expect(tabela(resultado)).to eq([%w[Telefone WhatsApp Nome], ['33330001', '(11) 987650001', 'Ana']])

    a_esquerda = juntar("Nome,Celular,Cod. Area\nAna,987650001,11\n")
    expect(tabela(a_esquerda)).to eq([%w[Nome Celular], ['Ana', '(11) 987650001']])
  end

  it 'com título de DDD e nenhuma coluna com título de telefone, junta com a coluna logo à direita' do
    resultado = juntar("Nome,DDD,Fone\nAna,11,987650001\n")

    expect(tabela(resultado)).to eq([%w[Nome Fone], ['Ana', '(11) 987650001']])
  end

  it 'junta a coluna sem título colada à esquerda da coluna de telefone quando ela só tem DDDs' do
    resultado = juntar("Nome,,Celular\nAna,11,987650001\nBia,,21987650002\nCaio,31,987650003\n")

    expect(resultado.juntadas).to eq(2)
    expect(tabela(resultado)).to eq([%w[Nome Celular], ['Ana', '(11) 987650001'], %w[Bia 21987650002], ['Caio', '(31) 987650003']])
  end

  it 'não mexe na coluna com outro título, mesmo colada ao telefone e só com números de dois dígitos' do
    arquivo = planilha("Nome,Idade,Celular\nAna,21,987650001\nBia,35,987650002\n")

    resultado = described_class.new(arquivo).call

    expect(resultado.juntadas).to eq(0)
    expect(resultado.arquivo).to equal(arquivo)
  end

  it 'não mexe na coluna sem título que tem algum valor que não é DDD, nem na que está à direita do telefone' do
    ["Nome,,Celular\nAna,11,987650001\nBia,20,987650002\n", "Nome,,Celular\nAna,11,987650001\nBia,sim,987650002\n",
     "Nome,Celular,\nAna,987650001,11\n", "Nome,,Celular\nAna,,987650001\n"].each do |texto|
      arquivo = planilha(texto)

      expect(described_class.new(arquivo).call.arquivo).to equal(arquivo), texto
    end
  end

  it 'na linha com DDD que não existe, o número segue sem DDD; as outras linhas são juntadas' do
    resultado = juntar("Nome,DDD,Celular\nAna,20,987650001\nBia,5,987650002\nCaio,00,987650003\nDavi,11,987650004\nEva,,987650005\n")

    expect(resultado.juntadas).to eq(1)
    expect(tabela(resultado).drop(1)).to eq([%w[Ana 987650001], %w[Bia 987650002], %w[Caio 987650003], ['Davi', '(11) 987650004'], %w[Eva 987650005]])
  end

  it 'deixa como está o número que já veio com DDD ou com o código do país' do
    resultado = juntar("Nome,DDD,Celular\nAna,11,11987650001\nBia,11,+55 11 98765-0002\nCaio,11,(11) 98765-0003\nDavi,11,123\n")

    expect(resultado.juntadas).to eq(0)
    expect(tabela(resultado).drop(1)).to eq([%w[Ana 11987650001], ['Bia', '+55 11 98765-0002'], ['Caio', '(11) 98765-0003'], %w[Davi 123]])
  end

  it 'acha o título abaixo de linhas soltas no começo da planilha e mantém o número de cada linha' do
    resultado = juntar("Clientes de 2025,,\n,,\nNome,DDD,Celular\nAna,11,987650001\n")

    expect(tabela(resultado)).to eq([['Clientes de 2025', ''], ['', ''], %w[Nome Celular], ['Ana', '(11) 987650001']])
    expect(resultado.arquivo.tables.first.rows.map(&:row_number)).to eq([1, 2, 3, 4])
    # Como no leitor de planilhas: `headers` é a primeira linha da tabela, não a linha dos títulos.
    expect(resultado.arquivo.headers).to eq(['Clientes de 2025', ''])
  end

  it 'devolve o cabeçalho e as linhas como o leitor de planilhas os entrega, em CSV e em XLSX' do
    linhas = [%w[Nome DDD Celular], %w[Ana 11 987650001], %w[Bia 21 987650002]]
    arquivos = { 'lista.csv' => linhas.map { |linha| linha.join(',') }.join("\n"), 'lista.xlsx' => build_xlsx(linhas) }

    arquivos.each do |nome, conteudo|
      original = CampaignImports::Parser.new(StringIO.new(conteudo), filename: nome).perform
      # O que o leitor entrega: a primeira linha da primeira tabela é o cabeçalho, o resto são as linhas.
      expect(original.headers).to eq(original.tables.first.rows.first.values), nome
      expect(original.rows).to eq(original.tables.first.rows.drop(1)), nome

      juntado = described_class.new(original).call.arquivo

      expect(juntado.headers).to eq(%w[Nome Celular]), nome
      expect(juntado.headers).to eq(juntado.tables.first.rows.first.values), nome
      expect(juntado.rows).to eq(juntado.tables.first.rows.drop(1)), nome
      expect(juntado.rows.map(&:values)).to eq([['Ana', '(11) 987650001'], ['Bia', '(21) 987650002']]), nome
      expect(juntado.format).to eq(original.format), nome
    end
  end

  it 'não junta quando o DDD ou o número parece fórmula: a célula segue como veio, para a leitura acusar a fórmula' do
    resultado = juntar("Nome,DDD,Celular\nAna,11,=98765+4321\nBia,=11,987650002\nCaio,11,987650003\n")

    expect(resultado.juntadas).to eq(1)
    expect(tabela(resultado).drop(1)).to eq([['Ana', '=98765+4321'], %w[Bia 987650002], ['Caio', '(11) 987650003']])
  end

  it 'devolve a mesma planilha quando não há o que juntar' do
    arquivo = planilha("Nome,Celular,Email\nAna,11987650001,ana@exemplo.com.br\n")

    expect(described_class.new(arquivo).call).to have_attributes(arquivo: arquivo, juntadas: 0)
  end
end
