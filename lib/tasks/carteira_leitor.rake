# BATERIA PAGA DO LEITOR DE APÓLICE (E6, #2899), DESLIGADA POR PADRÃO. Chama o Carteira::Leitor de verdade (o modelo, as
# instruções e o esquema de produção) com os PDFs fictícios de spec/fixtures/carteira e compara com o gabarito.
#
#   AUTONOMIA_EVAL_PAGO=1 CARTEIRA_LEITOR_BATERIA=1 OPENAI_API_KEY=<chave de DESENVOLVIMENTO> \
#     bundle exec rake carteira:leitor:bateria
#
# Cada caso é uma chamada paga: FORA DO CI de propósito, e só roda com orçamento aprovado pelo dono. Sem as duas
# variáveis e a chave, a tarefa para antes de qualquer chamada. A chave nunca é impressa e nunca é a de produção.
# Em produção (`Rails.env.production?`) e na CI (variável `CI`) a tarefa para sempre, mesmo com tudo ligado: lá a
# chave seria a de produção, e na CI ninguém aprovou o gasto.
#
# Nada é gravado: a conta é um objeto em memória com a leitura liberada, e o cliente não registra uso no banco. Antes
# da primeira chamada, a estimativa pelo pior caso (todas as páginas que cabem numa pergunta, cheias, e a saída no
# teto) precisa ficar abaixo de TETO_USD; durante, o custo real (o `usage` que a API devolve, na tarifa de
# Crm::Ai::Pricing) para a bateria se passar dele. Chamada que quebra sem devolver `usage` não entra na soma.
#
# A bateria se passa por cliente do leitor (`create`) para somar o custo de cada resposta antes de devolvê-la.
#
# O aceite da E6 é "0 campo errado calado e 0 telefone que não é do segurado": campo com valor diferente do gabarito
# (ou com valor onde o gabarito diz que não pode haver) é ERRADO e reprova a bateria. Campo que o leitor deixou em "não
# achei" quando o gabarito tinha valor não reprova: é contado à parte, para acompanhar. A régua só compara valores (na
# forma de comparação da casa, Carteira::Chave); quem interpreta o PDF é o modelo avaliado.
#
# Os PDFs são fictícios (spec/fixtures/carteira/gerar.rb). Para rodar contra apólices reais, aponte
# CARTEIRA_LEITOR_GABARITO para um gabarito fora do versionamento; nunca commite apólice de cliente.
class CarteiraLeitorBateria
  LIGAR = %w[AUTONOMIA_EVAL_PAGO CARTEIRA_LEITOR_BATERIA].freeze
  CHAVE = 'OPENAI_API_KEY'.freeze
  COMO_LIGAR = "Bateria desligada. Ela chama o modelo de verdade e custa dinheiro: rode só com orçamento aprovado, com #{LIGAR.join('=1 ')}=1 " \
               "e #{CHAVE} (chave de desenvolvimento).".freeze
  PROIBIDA = 'A bateria do leitor de apólice não roda em produção nem na CI: ela chama o modelo de verdade e custa dinheiro.'.freeze
  AMBIENTE_DA_CI = 'CI'.freeze
  TETO_USD = 2.0
  # Estimativa generosa: instruções e esquema; uma página cheia (Paginas::MAXIMO_POR_PAGINA caracteres).
  TOKENS_FIXOS = 2_500
  TOKENS_POR_PAGINA = 2_000
  POR_MILHAO = 1_000_000.0
  GABARITO = 'spec/fixtures/carteira/gabarito.json'.freeze
  CONTEM = 'contem'.freeze

  class EstourouOTeto < StandardError; end

  def self.proibida?
    Rails.env.production? || ENV.fetch(AMBIENTE_DA_CI, nil).present?
  end

  def self.ligada?
    !proibida? && LIGAR.all? { |variavel| ENV.fetch(variavel, nil) == '1' } && ENV.fetch(CHAVE, nil).present?
  end

  # nil quando a bateria pode rodar; senão, o aviso para quem tentou.
  def self.por_que_nao_roda
    return PROIBIDA if proibida?

    COMO_LIGAR unless ligada?
  end

  # O pior caso de uma pergunta, em dólar, na tarifa do modelo do leitor.
  def self.teto_por_caso
    tarifa = Crm::Ai::Pricing.rate(Carteira::Leitor::Campos::MODEL)
    entrada = TOKENS_FIXOS + (Carteira::Leitor::Paginas::MAXIMO * TOKENS_POR_PAGINA)
    ((entrada * tarifa[:input]) + (Carteira::Leitor::Campos::MAX_OUTPUT_TOKENS * tarifa[:output])) / POR_MILHAO
  end

  # Compara um resultado com o caso do gabarito. Devolve { errados: [nomes], nao_achou: [nomes] }; só nomes de campo.
  def self.conferir(caso, resultado)
    return { errados: ['recusa'], nao_achou: [] } if resultado.recusa != caso['recusa']

    errados = caso.key?('paginas_enviadas') && caso['paginas_enviadas'] != resultado.paginas_enviadas ? ['paginas_enviadas'] : []
    # O que o leitor achou, certo ou a confirmar: a régua mede o valor, não quem vai confirmá-lo.
    achados = resultado.campos.merge(resultado.valores_a_confirmar)
    situacoes = caso.fetch('campos', {}).to_h { |campo, esperado| [campo, situacao(esperado, achados[campo])] }
    { errados: errados + situacoes.select { |_campo, situacao| situacao == :errado }.keys,
      nao_achou: situacoes.select { |_campo, situacao| situacao == :nao_achou }.keys }
  end

  def self.situacao(esperado, lido)
    return lido.nil? ? :certo : :errado if esperado.nil?
    return :nao_achou if lido.nil?

    igual?(esperado, lido) ? :certo : :errado
  end

  def self.igual?(esperado, lido)
    return esperado == lido unless lido.is_a?(String)

    forma = Carteira::Chave.seguradora(lido)
    return esperado[CONTEM].all? { |trecho| forma.include?(Carteira::Chave.seguradora(trecho)) } if esperado.is_a?(Hash)

    forma == Carteira::Chave.seguradora(esperado)
  end

  def initialize(cliente: nil, gabarito: ENV.fetch('CARTEIRA_LEITOR_GABARITO', nil).presence || Rails.root.join(GABARITO).to_s)
    @gabarito = gabarito
    @casos = JSON.parse(File.read(gabarito)).fetch('casos')
    @cliente = cliente || cliente_de_verdade
    @usd = 0.0
    @conta = Account.new(internal_attributes: { Carteira::Leitor::Liberado::ATRIBUTO => true })
  end

  # Devolve true quando nenhum caso teve campo errado. Imprime só nomes de campo e contagens.
  def rodar(saida: $stdout)
    previsto = self.class.teto_por_caso * @casos.size
    raise EstourouOTeto, format('estimativa de US$ %<usd>.4f passa do teto de US$ %<teto>.2f', usd: previsto, teto: TETO_USD) if previsto > TETO_USD

    saida.puts format('%<n>d casos. Pior caso estimado: US$ %<usd>.4f (teto US$ %<teto>.2f).', n: @casos.size, usd: previsto, teto: TETO_USD)
    conferidos = @casos.map { |caso| rodar_caso(caso, saida) }
    fechar(conferidos, saida)
  end

  # O leitor chama `create` aqui: a bateria repassa ao cliente e soma o custo da resposta.
  def create(**opcoes)
    saida = @cliente.create(**opcoes)
    @usd += Crm::Ai::UsageRecorder.cost_for(opcoes[:model], Crm::Ai::UsageRecorder.extract_tokens(saida[:usage])).to_f
    saida
  end

  # O cliente de verdade leva a chave: o `inspect` e o `as_json` não mostram nada de dentro do objeto. (O mesmo do
  # Carteira::Leitor::Reservado, escrito aqui porque este arquivo é carregado antes de a aplicação subir.)
  def inspect
    "#<#{self.class.name}>"
  end

  def as_json(*)
    { 'classe' => self.class.name }
  end

  private

  # O único caminho que paga: recusa de novo aqui, para ninguém chegar ao modelo por fora da tarefa.
  def cliente_de_verdade
    raise ArgumentError, self.class.por_que_nao_roda unless self.class.ligada?

    credencial = { api_key: ENV.fetch(CHAVE), api_base: ENV.fetch('OPENAI_API_BASE', nil).presence, source: :bateria }
    # Sem nova tentativa: o teto de gasto conta uma chamada por caso.
    Crm::Ai::ResponsesClient.new(credential: credencial, max_retries: 0)
  end

  def rodar_caso(caso, saida)
    raise EstourouOTeto, format('custo real de US$ %<usd>.4f passou do teto', usd: @usd) if @usd > TETO_USD

    arquivo = File.join(File.dirname(@gabarito), caso.fetch('arquivo'))
    resultado = Carteira::Leitor.new(account: @conta, ocr: caso['ocr'] == true, cliente: self)
                                .ler(arquivo, documento: caso['documento'], nome: caso['nome_do_segurado'])
    conferido = self.class.conferir(caso, resultado)
    saida.puts linha(caso, resultado, conferido)
    conferido
  end

  def linha(caso, resultado, conferido)
    nomes = conferido.transform_values { |campos| campos.join(', ').presence || '-' }
    format('%<veredito>-7s %<nome>s | páginas %<enviadas>d de %<total>s | errados: %<errados>s | não achou: %<nao_achou>s',
           veredito: conferido[:errados].empty? ? 'ok' : 'ERRADO', nome: caso['nome'], enviadas: resultado.paginas_enviadas.size,
           total: resultado.paginas_total.inspect, errados: nomes[:errados], nao_achou: nomes[:nao_achou])
  end

  def fechar(conferidos, saida)
    errados = conferidos.sum { |conferido| conferido[:errados].size }
    nao_achou = conferidos.sum { |conferido| conferido[:nao_achou].size }
    saida.puts format('Campos errados: %<errados>d (o aceite é 0). Campos em "não achei" que o gabarito tinha: %<nao_achou>d. ' \
                      'Custo real: US$ %<usd>.4f.', errados: errados, nao_achou: nao_achou, usd: @usd)
    errados.zero?
  end
end

namespace :carteira do
  namespace :leitor do
    desc 'Bateria paga do leitor de apólice contra o gabarito (desligada por padrão; ver o cabeçalho do arquivo)'
    task bateria: :environment do
      aviso = CarteiraLeitorBateria.por_que_nao_roda
      abort aviso if aviso
      exit(1) unless CarteiraLeitorBateria.new.rodar
    end
  end
end
