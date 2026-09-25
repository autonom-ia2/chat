require 'rails_helper'

# R18 DA RECEITA DE RAMO: NADA DE REGEX PARA ENTENDER O CLIENTE (regra do Rodrigo, 20/09/2026).
#
# Regex nunca interpreta o que uma pessoa escreveu: quem entende linguagem é o modelo. Fora disso, regex é o último
# recurso. Esta guarda varre, por AST (`VarreduraDaReceita::Regex`), o código da cotação, dos especialistas e da
# operação do agente, e compara cada uso com a lista abaixo. Uso novo fora da lista reprova; uso da lista que sumiu
# também, para a lista não envelhecer.
#
# O QUE CONTA COMO USO: literal `/.../` e `%r{...}` (também dentro de `gsub`, `split`, `scan`, `when`), `Regexp.new`,
# `Regexp.union`, `Regexp.escape`, `Regexp.last_match`, todo `=~`, `!~`, `match` e `match?`, `$~` e `$1`, e
# `gsub`/`sub`/`scan`/`split`/`start_with?`/`grep`... com uma CONSTANTE de regex como padrão.
#
# COMO ENTRAR NA LISTA: com o arquivo, onde está, o tipo e o trecho exatamente como a mensagem de erro os imprime, o
# motivo em uma frase, e `pessoa:` dizendo o que o padrão lê:
#   :nao            não lê texto de pessoa (texto do modelo, do portal, nosso, ou de configuração);
#   :sem_interpretar lê texto de pessoa só para normalizar ou recusar forma, sem decidir o que ela quis dizer;
#   :achado          parece interpretar texto de pessoa: não se corrige aqui, vai para o Rodrigo decidir.
# Regex que interpreta texto de pessoa NÃO ENTRA com outro rótulo: a regra manda tirar.
module RegexDaReceita
  RAIZES = %w[
    app/services/autonomia/insurance
    app/services/autonomia/agents/tools/native/insurance_quote.rb
    app/services/autonomia/agents/tools/native/insurance_quote_proposal.rb
    app/services/autonomia/agents/tools/native/insurance_quote_result.rb
    app/services/autonomia/agents/tools/native/insurance_quote
    app/services/autonomia/agents/specialists
    app/services/autonomia/agents/operate
  ].freeze

  CHUNKER = 'app/services/autonomia/agents/operate/reply_chunker.rb'.freeze
  C = '::Autonomia::Agents::Operate::ReplyChunker'.freeze
  RESPONDER = 'app/services/autonomia/agents/operate/responder.rb'.freeze
  R = '::Autonomia::Agents::Operate::Responder'.freeze
  PROPOSTA = 'app/services/autonomia/agents/tools/native/insurance_quote_proposal.rb'.freeze
  P = '::Autonomia::Agents::Tools::Native::InsuranceQuoteProposal'.freeze
  SYNC = 'app/services/autonomia/insurance/connections/sync.rb'.freeze
  S = '::Autonomia::Insurance::Connections::Sync'.freeze
  BUILDER = 'app/services/autonomia/insurance/quote_agent/builder.rb'.freeze
  B = '::Autonomia::Insurance::QuoteAgent::Builder'.freeze

  # O fatiador divide a RESPOSTA DO MODELO em mensagens de WhatsApp: forma do texto (parágrafo, item de lista,
  # abreviação, valor que não pode ser partido), nunca o que o cliente quis dizer.
  FATIADOR = 'fatiador da resposta do modelo em mensagens de WhatsApp; lê a forma do texto do modelo, não o cliente'.freeze

  EXCECOES = [
    { arquivo: CHUNKER, onde: "#{C}::URL_REGEX", tipo: 'literal', trecho: '%r{https?://[^\s<>"]+}i', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::PROTECT_PATTERNS", tipo: 'literal', trecho: '/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i',
      pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::PROTECT_PATTERNS", tipo: 'literal', trecho: '%r{\b\d{2}/\d{2}/\d{4}\b}', pessoa: :nao,
      motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::PROTECT_PATTERNS", tipo: 'literal', trecho: '/\b\d{1,3}(?:\.\d{3})*,\d{2}\b/', pessoa: :nao,
      motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::PROTECT_PATTERNS", tipo: 'literal', trecho: '/\b[A-Z]{2,}[- ]?\d[A-Z0-9-]*\b/i', pessoa: :nao,
      motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::PROTECT_PATTERNS", tipo: 'literal', trecho: '/\b\d+[.,]\d+\b/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::ABBREVIATION_RE", tipo: 'literal', trecho: '/\b(?:Dr|Dra|Sr|Sra|Srta|etc|vs|aprox|obs|Ref|Ex)\./i',
      pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::LIST_ITEM_RE", tipo: 'literal', trecho: '/\A\s*(?:[-*•]\s+|\d+[.)]\s+)/', pessoa: :nao,
      motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}::TOKEN_RE", tipo: 'literal', trecho: "/\#{[0xE000].pack('U')}(\\d+)\#{[0xE001].pack('U')}/",
      pessoa: :nao, motivo: 'marcador nosso, de área privada do Unicode, que o fatiador põe e tira do texto' },
    { arquivo: CHUNKER, onde: "#{C}#normalize", tipo: 'literal', trecho: '/[\u200B\u200C\u200D\uFEFF]/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#normalize", tipo: 'literal', trecho: '/[ \t]+\n/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#normalize", tipo: 'literal', trecho: '/\n{3,}/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#normalize", tipo: 'literal', trecho: '/[ \t]{2,}/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#normalize", tipo: 'literal', trecho: '/\*\*(.+?)\*\*/m', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#build_chunks", tipo: 'literal', trecho: '/\n{2,}/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#url_only?", tipo: 'match?', trecho: 'match?(URL_REGEX)', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#url_only?", tipo: 'sub(constante)', trecho: "sub(URL_REGEX, '')", pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#list_run_flags", tipo: 'match?', trecho: 'match?(LIST_ITEM_RE)', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#split_long", tipo: 'literal', trecho: '/\s+/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#protect", tipo: 'gsub(constante)', trecho: 'gsub(TOKEN_RE)', pessoa: :nao,
      motivo: 'devolve ao texto o trecho protegido pelo marcador nosso' },
    { arquivo: CHUNKER, onde: "#{C}#protect", tipo: 'Regexp.last_match', trecho: 'Regexp.last_match(1)', pessoa: :nao,
      motivo: 'o número do marcador nosso que o gsub acima casou' },
    { arquivo: CHUNKER, onde: "#{C}#merge_two", tipo: 'match?', trecho: 'match?(LIST_ITEM_RE)', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#merge_two", tipo: 'literal', trecho: '/[ \t]{2,}/', pessoa: :nao, motivo: FATIADOR },
    { arquivo: CHUNKER, onde: "#{C}#text_delay", tipo: 'literal', trecho: '/\s+/', pessoa: :nao,
      motivo: 'conta palavras da resposta do modelo para o tempo de digitação' },
    { arquivo: CHUNKER, onde: "#{C}#text_delay", tipo: 'literal', trecho: '/(?:\A|\n)\s*(?:[-*•]\s+|\d+[.)]\s+)/', pessoa: :nao,
      motivo: 'acha item de lista na resposta do modelo para o tempo de digitação' },
    { arquivo: RESPONDER, onde: "#{R}#normalize_token", tipo: 'literal', trecho: %q(/\A["'`*\s]+|["'`*\s]+\z/), pessoa: :nao,
      motivo: 'tira aspas e asterisco das pontas da resposta do modelo para compará-la ao token de silêncio' },
    { arquivo: RESPONDER, onde: "#{R}#already_replied?", tipo: 'Regexp.escape', trecho: 'Regexp.escape(@reply_to_message_id.to_s)',
      pessoa: :nao, motivo: 'escapa o id da mensagem (número nosso) para o padrão da consulta SQL de idempotência' },
    { arquivo: 'app/services/autonomia/agents/tools/native/insurance_quote/comparativo.rb',
      onde: '::Autonomia::Agents::Tools::Native::InsuranceQuote::Comparativo#nome_do_comparativo', tipo: 'literal',
      trecho: '/[^A-Z0-9]/', pessoa: :sem_interpretar,
      motivo: 'tira da placa o que não é letra ou dígito para o nome do arquivo PDF; String#delete faria o mesmo sem regex' },
    { arquivo: PROPOSTA, onde: "#{P}#enviar", tipo: 'match?', trecho: 'match?(Arquivo::URL_SEGURA)', pessoa: :nao,
      motivo: 'confere que a URL que o adapter devolveu é https antes de baixar' },
    { arquivo: PROPOSTA, onde: "#{P}#nome_do_arquivo", tipo: 'literal', trecho: '/[^A-Z0-9]/', pessoa: :sem_interpretar,
      motivo: 'tira da placa o que não é letra ou dígito para o nome do arquivo PDF; String#delete faria o mesmo sem regex' },
    { arquivo: PROPOSTA, onde: "#{P}#nome_do_arquivo", tipo: 'literal', trecho: '%r{[/\\\\:]}', pessoa: :nao,
      motivo: 'tira do nome da seguradora, que vem do portal, o que o sistema do cliente recusa em nome de arquivo' },
    { arquivo: SYNC, onde: "#{S}::EMAIL", tipo: 'literal', trecho: '/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/', pessoa: :nao,
      motivo: 'redige e-mail da mensagem de erro do adapter antes do log' },
    { arquivo: SYNC, onde: "#{S}::LONG_TOKEN", tipo: 'literal', trecho: '/[A-Za-z0-9_\-.]{32,}/', pessoa: :nao,
      motivo: 'redige token da mensagem de erro do adapter antes do log' },
    { arquivo: SYNC, onde: "#{S}#sanitize", tipo: 'gsub(constante)', trecho: "gsub(LONG_TOKEN, '<redacted>')", pessoa: :nao,
      motivo: 'redige token da mensagem de erro do adapter antes do log' },
    { arquivo: SYNC, onde: "#{S}#sanitize", tipo: 'gsub(constante)', trecho: "gsub(EMAIL, '<email>')", pessoa: :nao,
      motivo: 'redige e-mail da mensagem de erro do adapter antes do log' },
    { arquivo: 'app/services/autonomia/insurance/connector/mock/leituras.rb',
      onde: '::Autonomia::Insurance::Connector::Mock::Leituras#vehicle_lookup', tipo: 'literal', trecho: '/[^A-Za-z0-9]/',
      pessoa: :sem_interpretar, motivo: 'o dublê do adapter (teste e desenvolvimento) normaliza a placa como o adapter real' },
    { arquivo: BUILDER, onde: "#{B}#substituir", tipo: 'gsub(constante)', trecho: 'gsub(MARCADOR)', pessoa: :nao,
      motivo: 'troca os marcadores nossos do manual da Lia pelas escolhas da corretora, numa passada só' },
    { arquivo: BUILDER, onde: "#{B}#conferir_escolhas!", tipo: 'match?', trecho: 'MARCADOR.match?(valor.to_s)',
      pessoa: :sem_interpretar, motivo: 'recusa marcador reservado dentro do nome ou horário que a corretora digitou' },
    { arquivo: BUILDER, onde: "#{B}::MARCADOR", tipo: 'literal', trecho: '/(?:#{Regexp.union(VARIAVEIS.keys).source})\b/', # rubocop:disable Lint/InterpolationCheck
      pessoa: :nao, motivo: 'os quatro marcadores nossos do manual da Lia, com fronteira de palavra' },
    { arquivo: BUILDER, onde: "#{B}::MARCADOR", tipo: 'Regexp.union', trecho: 'Regexp.union(VARIAVEIS.keys)', pessoa: :nao,
      motivo: 'os quatro marcadores nossos do manual da Lia, com fronteira de palavra' },
    { arquivo: BUILDER, onde: "#{B}#validar_escolhas!", tipo: 'match?', trecho: 'MARCADOR.match?(valor)', pessoa: :sem_interpretar,
      motivo: 'recusa marcador reservado dentro do nome que a corretora digitou' },
    { arquivo: BUILDER, onde: "#{B}#validar_escolhas!", tipo: 'match?', trecho: 'MARCADOR.match?(@horario)', pessoa: :sem_interpretar,
      motivo: 'recusa marcador reservado dentro do horário que a corretora digitou' },
    { arquivo: 'app/services/autonomia/insurance/quote_input.rb', onde: '::Autonomia::Insurance::QuoteInput#digitos',
      tipo: 'literal', trecho: '/\D/', pessoa: :sem_interpretar,
      motivo: 'só os dígitos do CPF, CNPJ ou CEP que o modelo escreveu; String#delete faria o mesmo sem regex' },
    # ACHADO PARA O RODRIGO (25/09/2026). As palavras do campo `seguradora`, que o modelo escreve "como a pessoa disse",
    # são casadas por palavra com os nomes das seguradoras para decidir de qual ela fala (`#procurar`), e as da fala
    # da Lia, para achar a seguradora citada (`ConferenciaDePrecos#citadas`). Não é lista de intenção, mas decide o
    # que a pessoa pediu por casamento de palavra, e não pelo modelo. Não corrigido aqui, por regra da tarefa.
    { arquivo: 'app/services/autonomia/insurance/resultado_da_cotacao.rb',
      onde: '::Autonomia::Insurance::ResultadoDaCotacao#palavras', tipo: 'literal', trecho: '/[a-z0-9]+/', pessoa: :achado,
      motivo: 'quebra em palavras o nome de seguradora pedido pela pessoa para casar com os nomes da cotação' }
  ].freeze

  PESSOA = %i[nao sem_interpretar achado].freeze

  module_function

  def usos
    VarreduraDaReceita::Regex.usos(VarreduraDaReceita.arquivos(RAIZES))
  end

  def chave(excecao)
    excecao.values_at(:arquivo, :onde, :tipo, :trecho)
  end
end

RSpec.describe 'R18: nada de regex para entender o cliente' do # rubocop:disable RSpec/DescribeClass
  let(:usos) { RegexDaReceita.usos }
  let(:permitidos) { RegexDaReceita::EXCECOES.map { |excecao| RegexDaReceita.chave(excecao) } }

  it 'nenhum uso de regex fora da lista de exceções' do
    novos = usos.reject { |uso| permitidos.include?(uso.chave) }

    expect(novos).to be_empty, <<~MSG
      Regex nova no código da cotação. Regex nunca interpreta o que uma pessoa escreveu (quem entende é o modelo), e
      fora disso é o último recurso: prefira método de string, parser ou schema. Se não houver alternativa, pergunte ao
      Rodrigo e, com o OK dele, entre em RegexDaReceita::EXCECOES com o motivo:
      #{novos.join("\n")}
    MSG
  end

  it 'cada exceção da lista existe no código, uma vez por entrada' do
    contagem = usos.map(&:chave).tally
    esperada = permitidos.tally

    expect(contagem.select { |chave, _| esperada.key?(chave) }).to eq(esperada),
                                                                   'exceção da lista que sumiu ou mudou: tire da lista ou atualize o trecho'
  end

  it 'cada exceção diz o que o padrão lê e por quê' do
    RegexDaReceita::EXCECOES.each do |excecao|
      expect(RegexDaReceita::PESSOA).to include(excecao[:pessoa]), excecao.inspect
      expect(excecao[:motivo].to_s.strip).not_to be_empty, excecao.inspect
    end
  end

  # AUTOTESTE: um visitador quebrado devolveria lista vazia, e a guarda passaria elogiando o silêncio.
  it 'a varredura enxerga as regex que existem, cada forma de uso' do
    tipos = usos.map(&:tipo).uniq

    expect(usos.size).to be >= RegexDaReceita::EXCECOES.size
    expect(tipos).to include('literal', 'match?', 'gsub(constante)', 'Regexp.union', 'Regexp.escape')
  end

  # O que a guarda reconhece como uso, provado num código de mentira: o que o Prism vê é o que a guarda cobra.
  it 'reconhece literal, Regexp, =~, match, constante de regex como padrão, when e captura' do
    codigo = <<~RUBY
      class Teste
        PADRAO = /x/.freeze
        def a(t) = t =~ /y/
        def b(t) = Regexp.new(t)
        def c(t) = t.match?('z')
        def d(t) = t.split(PADRAO)
        def e(t)
          case t
          when PADRAO then $1
          end
        end
        def f(t) = t.split(',')
      end
    RUBY
    raiz = Prism.parse(codigo).value
    constantes = VarreduraDaReceita::Regex.constantes_de_regex(raiz)
    achados = VarreduraDaReceita::Regex.usos_em('teste.rb', raiz, constantes)

    expect(achados.map { |achado| [achado.onde, achado.tipo] }).to contain_exactly(
      ['::Teste::PADRAO', 'literal'], ['::Teste#a', 'literal'], ['::Teste#a', '=~'], ['::Teste#b', 'Regexp.new'],
      ['::Teste#c', 'match?'], ['::Teste#d', 'split(constante)'], ['::Teste#e', 'when'], ['::Teste#e', 'captura']
    )
  end

  it 'os achados para o Rodrigo decidir estão marcados, e só eles' do
    achados = RegexDaReceita::EXCECOES.select { |excecao| excecao[:pessoa] == :achado }.map { |excecao| excecao[:onde] }

    expect(achados).to eq(['::Autonomia::Insurance::ResultadoDaCotacao#palavras'])
  end
end
