require 'rails_helper'

# #2896 — "Trazer minha lista": a contagem dos valores da coluna que diz quem é cliente e a chave de cada valor. O
# contrato da rota está em spec/requests/api/v1/accounts/relacionamentos_trazer_valores_cliente_spec.rb; aqui, o
# agrupamento e a chave.
RSpec.describe ContactImports::Trazer::ValoresDeCliente, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  def lida(texto, destinos: { '2' => 'cliente' })
    importacao = create_contact_import(account: account, user: user, content: texto)
    importacao.update!(options: importacao.options.merge('trazer' => { 'destinos' => destinos }))
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  def planilha(celulas)
    linhas = celulas.each_with_index.map { |celula, numero| "Pessoa #{numero};119876500#{format('%02d', numero)};#{celula}" }
    "Nome;Celular;Situação\n#{linhas.join("\n")}\n"
  end

  def contagem(importacao)
    described_class.new(importacao).da_coluna(2)
  end

  # A chave de um valor da coluna "Situação" (2) desta importação.
  def chave(importacao, valor)
    ContactImports::Trazer::Cliente.chave(importacao.id, 2, valor)
  end

  it 'a leitura da planilha conta os valores da coluna "cliente" e guarda num arquivo pequeno da importação' do
    importacao = lida(planilha(['Ativo', 'inativo', 'ATIVO', '', 'Ativo', ' ativo ']))

    expect(importacao.valores_cliente).to be_attached
    expect(contagem(importacao)).to eq(
      'preenchidas' => 5, 'outros' => nil,
      'valores' => [{ 'chave' => chave(importacao, 'ativo'), 'valor' => 'Ativo', 'linhas' => 4 },
                    { 'chave' => chave(importacao, 'INATIVO'), 'valor' => 'inativo', 'linhas' => 1 }]
    )
    # De outra coluna, ou sem coluna "cliente", não há contagem.
    expect(described_class.new(importacao).da_coluna(1)).to eq('preenchidas' => 0, 'valores' => [], 'outros' => nil)
    expect(lida(planilha(%w[Ativo]), destinos: {}).valores_cliente).not_to be_attached
  end

  it 'junta o que só muda em espaço nas pontas e em maiúscula; acento e palavra a mais são outro valor' do
    importacao = lida(planilha(['Não', 'NÃO', 'nao', 'Não mesmo', 'não']))

    expect(contagem(importacao)['valores'].pluck('valor', 'linhas')).to eq([['Não', 3], ['nao', 1], ['Não mesmo', 1]])
  end

  # O espaço que não quebra linha (U+00A0), comum no que vem do Excel, é espaço como outro qualquer.
  it 'junta também o que só muda em espaço que não quebra linha ou em espaço a mais no meio, e mostra o valor sem eles' do
    colado = "\u00A0"
    importacao = lida(planilha(["Sim#{colado}", "#{colado}Sim#{colado}#{colado}", 'Sim', "Não#{colado}#{colado}mesmo", 'Não  mesmo', colado]))

    expect(contagem(importacao)).to eq(
      'preenchidas' => 5, 'outros' => nil,
      'valores' => [{ 'chave' => chave(importacao, 'sim'), 'valor' => 'Sim', 'linhas' => 3 },
                    { 'chave' => chave(importacao, 'não mesmo'), 'valor' => 'Não mesmo', 'linhas' => 2 }]
    )
  end

  it 'no empate vale a ordem da planilha, tanto entre os valores quanto entre as formas de escrever um deles' do
    importacao = lida(planilha(%w[b A a B c]))

    expect(contagem(importacao)['valores'].pluck('valor', 'linhas')).to eq([['b', 2], ['A', 2], ['c', 1]])
  end

  it 'guarda só os 20 mais frequentes e a soma dos outros' do
    importacao = lida(planilha((1..23).map { |numero| "valor #{numero}" } + ['valor 23']))

    guardada = JSON.parse(importacao.valores_cliente.download)
    expect(guardada['valores'].size).to eq(20)
    expect(guardada['valores'].first).to include('valor' => 'valor 23', 'linhas' => 2)
    expect(guardada).to include('coluna' => 2, 'preenchidas' => 24, 'outros' => { 'valores' => 3, 'linhas' => 3 })
  end

  # A célula pode ter um texto longo (uma observação inteira), e o valor vai para a tela e para o arquivo.
  it 'mostra cada valor com no máximo 120 caracteres; o agrupamento e a chave continuam sendo do valor inteiro' do
    comum = 'Cliente desde a inauguração da loja do centro, ' * 3
    da_ana = "#{comum}atendido pela Ana"
    do_bruno = "#{comum}atendido pelo Bruno"
    importacao = lida(planilha([da_ana, do_bruno, da_ana.upcase, 'ç' * 120, 'ç' * 121]))

    valores = contagem(importacao)['valores']

    # Dois valores diferentes que ficam iguais depois do corte continuam sendo dois, cada um com a sua chave.
    cortado = "#{comum.first(119)}…"
    expect(valores.pluck('valor', 'linhas')).to eq([[cortado, 2], [cortado, 1], ['ç' * 120, 1], ["#{'ç' * 119}…", 1]])
    expect(valores.pluck('chave')).to eq([da_ana, do_bruno, 'ç' * 120, 'ç' * 121].map { |valor| chave(importacao, valor) })
    expect(valores.pluck('chave').uniq.size).to eq(4)
    expect(valores.pluck('valor').map(&:size)).to eq([120, 120, 120, 120])
    expect(JSON.parse(importacao.valores_cliente.download)['valores'].pluck('valor').map(&:size).max).to eq(120)
  end

  it 'conta de novo pelas linhas que a leitura gravou, com o mesmo resultado' do
    importacao = lida(planilha(['Ativo', 'inativo', 'ATIVO', '']))
    da_leitura = contagem(importacao)

    described_class.new(importacao).contar(2)

    expect(contagem(importacao.reload)).to eq(da_leitura)
  end

  describe ContactImports::Trazer::Cliente do
    it 'a chave é a mesma para o mesmo valor agrupado e não é um resumo que se refaz sem o segredo da aplicação' do
      expect(described_class.chave(7, 2, "  SIM\u00A0")).to eq(described_class.chave(7, 2, 'sim'))
      expect(described_class.chave(7, 2, 'Sim  desde 2019')).to eq(described_class.chave(7, 2, 'sim desde 2019'))
      expect(described_class.chave(7, 2, 'sim').size).to eq(64)
      expect(described_class.chave(7, 2, 'sim')).not_to eq(described_class.chave(7, 2, 'são'))
      expect(described_class.chave(7, 2, 'nao')).not_to eq(described_class.chave(7, 2, 'não'))
      expect(described_class.chave(7, 2, 'sim')).not_to eq(Digest::SHA256.hexdigest('sim'))
    end

    # Com a chave só do texto, qualquer conta serviria de dicionário e duas colunas trocariam chave entre si.
    it 'a chave é da importação e da coluna: o mesmo valor noutra importação ou noutra coluna tem outra chave' do
      expect(described_class.chave(7, 2, 'sim')).not_to eq(described_class.chave(8, 2, 'sim'))
      expect(described_class.chave(7, 2, 'sim')).not_to eq(described_class.chave(7, 3, 'sim'))
      # O número da importação e o da coluna não se misturam um com o outro, nem com o valor.
      expect(described_class.chave(1, 23, 'sim')).not_to eq(described_class.chave(12, 3, 'sim'))
      expect(described_class.chave(1, 2, '3 sim')).not_to eq(described_class.chave(1, 23, 'sim'))
      expect(described_class.chave('7', '2', 'sim')).to eq(described_class.chave(7, 2, 'sim'))
      expect { described_class.chave(7, 'dois', 'sim') }.to raise_error(ArgumentError)
    end

    # respostas: as da conferência, ou um bloco que as monta com a importação já criada.
    def cliente(respostas)
      importacao = create_contact_import(account: account, user: user, content: "Nome;Celular;Situação\nAna;11987650001;Ativo\n")
      respostas = respostas.call(importacao) if respostas.respond_to?(:call)
      importacao.update!(options: importacao.options.merge('trazer' => { 'destinos' => { '2' => 'cliente' }, 'respostas' => respostas }))
      ContactImports::Validator.new(importacao).perform
      described_class.new(importacao.reload)
    end

    it 'sem a escolha da pessoa ninguém é cliente, diga a célula o que disser' do
      sem_escolha = cliente({})

      ['Sim', 'sim', 'x', 'cliente', 'true', '1', 'Ativo', '', nil].each do |valor|
        expect(sem_escolha.marca?('Situação' => valor)).to be(false), valor.inspect
      end
    end

    it 'marca pelo que a pessoa escolheu: a célula preenchida, ou a célula com um dos valores escolhidos' do
      preenchidas = cliente('valores_cliente' => { 'modo' => 'preenchidas' })
      escolhidos = cliente(->(importacao) { { 'valores_cliente' => { 'modo' => 'valores', 'chaves' => [chave(importacao, 'ativo')] } } })

      expect(%w[Ativo não x].map { |valor| preenchidas.marca?('Situação' => valor) }).to eq([true, true, true])
      expect(['', ' ', nil].map { |valor| preenchidas.marca?('Situação' => valor) }).to eq([false, false, false])
      expect(preenchidas.marca?({})).to be(false)
      expect(['Ativo', ' ATIVO ', 'ativo', "Ativo\u00A0"].map { |valor| escolhidos.marca?('Situação' => valor) }).to eq([true] * 4)
      expect(['Ativo sim', 'inativo', 'sim', '', nil].map { |valor| escolhidos.marca?('Situação' => valor) }).to eq([false] * 5)
      # Só a coluna que diz quem é cliente conta: o mesmo valor noutra coluna não marca ninguém.
      expect(escolhidos.marca?('Plano' => 'Ativo')).to be(false)
    end

    it '"sim, todas" marca todo mundo, com ou sem coluna' do
      expect(cliente('clientes' => 'sim_todas').marca?({})).to be(true)
    end
  end
end
