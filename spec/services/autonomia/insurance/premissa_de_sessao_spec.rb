require 'rails_helper'

# A PREMISSA FALSA DA SESSAO UNICA NAO VOLTA — e ate esta rodada nada fazia a regra valer.
#
# A frase e "o AGGER aceita uma sessao viva por login, e abrir outra invalida a anterior". Foi medida
# duas vezes contra o portal real e e falsa: em 05/09/2026 sete logins em sequencia devolveram o
# MESMO id de sessao, com o token do primeiro respondendo 200 depois de todos os outros; em
# 10/09/2026 seis logins simultaneos coexistiram e doze sessoes fizeram 1.202 chamadas autenticadas
# em 30 s sem uma falha. O canario vivo mora no adapter
# (`autonomia-adapters/test/contract/agger.sessao-unica.live.test.ts`).
#
# POR QUE UMA GUARDA DE PROSA, se ninguem executa comentario. Porque esta frase e a que decide
# arquitetura: foi ela que gerou a issue `autonom-ia2/autonomia-adapters#8` ("fila por corretora") e
# e ela que faria o proximo engenheiro serializar cotacao por corretora — uma fila que nos tornaria o
# gargalo que o portal nao e. Tres rodadas seguidas de correcao acharam a mesma afirmacao em arquivos
# novos, INCLUSIVE dentro de arquivos que a rodada anterior tinha corrigido no cabecalho. Disciplina
# humana nao e regra, e intencao.
#
# A REGRA NAO E "A FRASE NAO APARECE". Toda correcao desta casa cita a frase falsa para poder
# refuta-la, e apagar a citacao apagaria o registro de por que a correcao existe. A regra e: **a
# frase nunca aparece longe da sua refutacao**. Quem refuta escreve a refutacao por perto; quem
# afirma, nao.
#
# O QUE ELA NAO PROMETE: le PROSA (comentario, titulo de exemplo e markdown), entao uma afirmacao
# dentro de uma string de codigo escapa; e casa PALAVRA, nao sentido — uma parafrase sem nenhuma
# destas palavras passa. Fecha a reincidencia medida, nao a criatividade. A gemea dela esta no
# adapter, em `test/unit/premissa-de-sessao-nao-volta.test.ts`, porque a premissa atravessa a
# fronteira dos dois repositorios.
module PremissaDeSessao
  RAIZES = [
    'app/services/autonomia/insurance',
    'app/models/autonomia/insurance',
    'app/controllers/api/v1/accounts/autonomia/insurance',
    'app/javascript/dashboard/routes/dashboard/autonomia/insurance',
    'spec/services/autonomia/insurance',
    'spec/models/autonomia/insurance',
    'docs/audit'
  ].freeze
  EXTENSOES = %w[.rb .js .vue .md].freeze

  # Este arquivo e o detector: as frases de amostra dentro dele sao o fixture da guarda, nao uma
  # afirmacao do repositorio. E o UNICO excluido, e o exemplo de contraprova nao depende dessa
  # exclusao para provar que o detector funciona.
  EU = 'premissa_de_sessao_spec.rb'.freeze

  # A afirmacao e a soma de duas coisas na mesma frase: algo CAINDO e o que cai sendo uma SESSAO.
  # Listas literais: uma forma nova entra aqui a mao, o que e mais visivel do que uma alternancia
  # escondida dentro de um padrao. As formas de "invalidar" sao VERBAIS de proposito — o prefixo cru
  # `invalid` acusaria "senha invalida" e "placa_invalida", e guarda que acusa o inocente e guarda
  # que alguem desliga.
  QUEDA = [
    'derrub', 'invalida a', 'invalidar', 'invalidaria', 'invalidou', 'invalidava', 'invalidad',
    'mata a sessao', 'troca o token', 'encerra a sessao', 'substituida por um login'
  ].freeze
  SESSAO = %w[sessao sessoes token].freeze

  # O que faz a citacao ser citacao. Sem um destes por perto, a frase esta sendo AFIRMADA.
  REFUTACAO = [
    'medid', 'medicao', 'falso', 'aqui se lia', 'correcao de', 'corrigid', 'canario',
    'reconciliado', 'nao derrub', 'nao e invalidad', 'nao invalida', 'coexist'
  ].freeze

  # Nomes de codigo que CARREGAM a palavra sem afirmar nada: `derrubaSessao` e o parametro do portal
  # e os outros dois sao o campo que o adapter devolve. Citar o nome de um campo nao e afirmar o que
  # ele diz — quem afirma e a prosa em volta, e essa continua sendo lida.
  NOMES_DE_CODIGO = %w[
    derrubaSessao droppedPreviousSession dropped_previous_session provar-link-nao-derruba
  ].freeze

  # A refutacao tem de caber no mesmo campo de visao de quem le o trecho. Doze linhas para cada lado
  # e o tamanho de um bloco de comentario desta casa — mais do que isso ja e "esta escrito noutro
  # lugar do arquivo", que foi exatamente o defeito das rodadas anteriores.
  LINHAS_DE_VIZINHANCA = 12

  ABERTURAS_DE_PROSA = ['#', '//', '*', '<!--'].freeze
  MARCAS_DE_TITULO = ["it '", 'it "', "describe '", 'describe "', "context '", 'context "'].freeze

  module_function

  def normalizar(texto)
    texto.downcase.tr('áàâãéêíóôõúüç', 'aaaaeeiooouuc')
  end

  # Fora das crases fica a prosa; dentro delas, codigo citado. Posicoes pares do `split` sao o de
  # fora, sem precisar de padrao.
  def fora_das_crases(linha)
    linha.split('`').each_with_index.filter_map { |parte, i| parte if i.even? }.join(' ')
  end

  def sem_nomes_de_codigo(linha)
    NOMES_DE_CODIGO.reduce(linha) { |texto, nome| texto.split(nome).join(' ') }
  end

  # Prosa e: comentario, titulo de exemplo e markdown. Uma linha de codigo que menciona um campo nao
  # afirma nada sobre o portal — acusa-la faria a guarda virar ruido, que e como guarda morre.
  def prosa?(arquivo, linha)
    return true if arquivo.end_with?('.md')

    texto = linha.strip
    ABERTURAS_DE_PROSA.any? { |a| texto.start_with?(a) } || MARCAS_DE_TITULO.any? { |m| linha.include?(m) }
  end

  # A frase pode estar quebrada em duas linhas — foi assim que um comentario ja corrigido no
  # cabecalho guardou a afirmacao no corpo do mesmo arquivo. Por isso cada linha de prosa e lida
  # junto da prosa seguinte.
  def afirmacoes_sem_refutacao(arquivo, conteudo)
    linhas = conteudo.split("\n")
    linhas.each_index.filter_map do |i|
      next unless prosa?(arquivo, linhas[i])

      seguinte = linhas[i + 1].to_s
      par = prosa?(arquivo, seguinte) ? "#{linhas[i]} #{seguinte}" : linhas[i]
      next unless afirma?(par)
      next if refutada_por_perto?(linhas, i)

      "#{arquivo}:#{i + 1}  #{linhas[i].strip[0, 110]}"
    end
  end

  def afirma?(par)
    frase = normalizar(sem_nomes_de_codigo(fora_das_crases(par)))
    QUEDA.any? { |q| frase.include?(q) } && SESSAO.any? { |s| frase.include?(s) }
  end

  def refutada_por_perto?(linhas, indice)
    inicio = [0, indice - LINHAS_DE_VIZINHANCA].max
    vizinhanca = normalizar(linhas[inicio..indice + LINHAS_DE_VIZINHANCA].join("\n"))
    REFUTACAO.any? { |r| vizinhanca.include?(r) }
  end

  def arquivos
    RAIZES.flat_map do |raiz|
      Dir.glob(Rails.root.join(raiz, '**', '*')).select do |caminho|
        File.file?(caminho) && EXTENSOES.any? { |e| caminho.end_with?(e) } &&
          File.basename(caminho) != EU
      end
    end
  end
end

RSpec.describe PremissaDeSessao do
  it 'nao acha a premissa afirmada longe da sua refutacao, no namespace de seguros' do
    achados = described_class.arquivos.flat_map do |caminho|
      relativo = Pathname.new(caminho).relative_path_from(Rails.root).to_s
      described_class.afirmacoes_sem_refutacao(relativo, File.read(caminho))
    end

    # A mensagem tem de dizer ONDE. Guarda que falha sem endereco e guarda que alguem desliga em vez
    # de atender.
    expect(achados).to eq([]), "a premissa voltou a ser afirmada em:\n#{achados.join("\n")}"
  end

  # A CONTRAPROVA. Sem ela, um erro no leitor (nao descer nas pastas, `prosa?` sempre falso) deixaria
  # a lista vazia para sempre e o exemplo passaria elogiando o proprio silencio — que e o defeito de
  # teste que esta entrega inteira esta corrigindo.
  it 'acusa a afirmacao, inclusive quebrada em duas linhas, e deixa passar a citacao que refuta' do
    # Arrange — o enchimento tira cada bloco da vizinhanca do outro: sem ele, a refutacao do segundo
    # bloco inocentaria o primeiro, e a amostra provaria menos do que parece.
    enchimento = ['enchimento = 0'] * (described_class::LINHAS_DE_VIZINHANCA + 1)
    amostra = [
      '# O AGGER aceita uma sessao viva por login: abrir outra invalida a anterior.', # linha 1
      *enchimento,
      '# Reusar a sessao e economia de login. (Aqui se lia "abrir outra invalida a anterior":', # 15
      '# medido e falso em 10/09/2026.)',
      *enchimento,
      'enviado = { derrubaSessao: true }', # 30 — codigo, nao prosa
      "it 'ainda repete o login com derrubaSessao' do", # 31 — titulo com o nome do parametro
      *enchimento,
      '# O healthcheck tem de tocar o portal com a sessao guardada — e sem fazer login,', # 45
      '# que invalidaria a cotacao em andamento.',
      *enchimento,
      '# Uma seguradora sem `configsSeg` nao pode derrubar a varredura inteira.' # 60 — cai, sem sessao
    ].join("\n")

    # Act
    achados = described_class.afirmacoes_sem_refutacao('amostra.rb', amostra)

    # Assert
    expect(achados.map { |a| a.split('  ').first }).to eq(['amostra.rb:1', 'amostra.rb:45'])
  end
end
