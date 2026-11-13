# A busca do passo "buscar informação em outro sistema" (#2934): um GET a um endereço escrito pela conta, e os dados da
# resposta JSON. Serve ao motor (PassoConsultar), ao "Fazer um teste" do editor e ao "Buscar agora" do ensaio.
#
# Segurança: a mesma régua do webhook (EnvioDoWebhook), porque o pedido sai do nosso servidor por um endereço que o dono
# da conta escreveu:
# - só https, sem usuário e senha no endereço e sem seguir redirecionamento;
# - nada de rede interna nem da própria plataforma: o nome é resolvido UMA vez aqui, todo IP é conferido
#   (EnvioDoWebhook.algum_interno?) e o SafeFetch conecta só nesses IPs (`resolver:` fixo). Sem segunda resolução não há
#   DNS rebinding;
# - prazo curto e resposta pequena: a busca acontece no meio de uma rodada do motor (ou de um pedido da tela).
#
# A resposta nunca leva o endereço nem o corpo cru: só os dados lidos, o código e a duração. Quem chama decide o que
# guarda; o histórico guarda só os nomes dos dados (PassoConsultar).
class Autonomia::Automacao::ConsultaDeFora
  ABRIR_EM = 3
  LER_EM = 5
  PRAZO_TOTAL = 8
  RESPOSTA_MAXIMA = 64.kilobytes
  # O teste mostra até isto de dados, no máximo neste fundo do JSON: o resto não cabe numa tela de escolher.
  DADOS_MAXIMOS = 50
  FUNDO_MAXIMO = 6
  # A régua do endereço é a do webhook; a frase é a deste passo.
  MOTIVOS_DO_ENDERECO = { 'webhook_so_https' => 'consulta_so_https', 'webhook_sem_senha_no_endereco' => 'consulta_sem_senha_no_endereco',
                          'webhook_endereco_interno' => 'consulta_endereco_interno' }.freeze

  Resposta = Struct.new(:motivo, :codigo, :ms, :dados, keyword_init: true) do
    def ok? = motivo.nil?
  end

  # Ao salvar e antes de buscar: o motivo de não servir, ou nil. O nome que resolve para rede interna só se descobre na
  # hora de buscar (o DNS muda).
  def self.problema_do_endereco(url)
    motivo = ::Autonomia::Automacao::EnvioDoWebhook.problema_do_endereco(url)
    motivo && MOTIVOS_DO_ENDERECO.fetch(motivo)
  end

  # O valor no `caminho` ("pedido.status", "itens.0.nome"): o número entra na lista; o caminho que passa por um valor
  # simples não acha nada.
  def self.valor_em(dados, caminho)
    caminho.to_s.split('.').reduce(dados) do |atual, parte|
      case atual
      when Hash then atual[parte]
      when Array then Integer(parte, 10, exception: false)&.then { |indice| atual[indice] }
      end
    end
  end

  # Os dados simples da resposta (texto, número, sim/não), na ordem em que vêm: [{ caminho:, valor: }].
  def self.achatar(dados, antes = nil, fundo = 0, lista = [])
    return lista if fundo > FUNDO_MAXIMO

    pares(dados).each do |chave, valor|
      break if lista.size >= DADOS_MAXIMOS

      guardar_em(lista, [antes, chave].compact.join('.'), valor, fundo)
    end
    lista
  end

  def self.pares(dados) = dados.is_a?(Array) ? dados.each_with_index.map { |valor, indice| [indice.to_s, valor] } : dados.to_a

  def self.guardar_em(lista, caminho, valor, fundo)
    return achatar(valor, caminho, fundo + 1, lista) if valor.is_a?(Hash) || valor.is_a?(Array)

    lista << { caminho: caminho, valor: valor } if simples?(valor)
  end

  def self.simples?(valor) = valor.is_a?(String) || valor.is_a?(Numeric) || [true, false].include?(valor)

  def initialize(url)
    @url = url.to_s
    @host = URI.parse(@url).hostname
  rescue URI::InvalidURIError
    @host = nil
  end

  def buscar
    motivo = self.class.problema_do_endereco(@url)
    return falhou(motivo) if motivo

    ips = Resolv.getaddresses(@host.to_s)
    return falhou('consulta_sem_resposta') if ips.empty?
    return falhou('consulta_endereco_interno') if ::Autonomia::Automacao::EnvioDoWebhook.algum_interno?(ips)

    ler(ips)
  end

  private

  # Conecta só nos IPs já conferidos: o SafeFetch não resolve o nome de novo.
  def ler(ips)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    conferidos = ips.map { |ip| IPAddr.new(ip) }
    texto = SafeFetch.fetch(@url, method: :get, headers: { 'Accept' => 'application/json', 'User-Agent' => 'Automacao-Consulta' },
                                  schemes: %w[https], max_redirects: 0, resolver: ->(_nome) { conferidos }, open_timeout: ABRIR_EM,
                                  read_timeout: LER_EM, total_timeout: PRAZO_TOTAL, max_bytes: RESPOSTA_MAXIMA,
                                  validate_content_type: false) { |resultado| resultado.tempfile.read }
    lido(texto, inicio)
  rescue SafeFetch::HttpError => e
    falhou('consulta_recusada', codigo: e.status, inicio: inicio)
  rescue SafeFetch::UnsafeUrlError, SafeFetch::InvalidUrlError, SafeFetch::CrossOriginRedirectError
    falhou('consulta_endereco_interno', inicio: inicio)
  rescue SafeFetch::FileTooLargeError
    falhou('consulta_resposta_grande', inicio: inicio)
  rescue SafeFetch::Error
    falhou('consulta_sem_resposta', inicio: inicio)
  end

  # Só objeto ou lista JSON: texto, número solto ou HTML não têm dado para guardar.
  def lido(texto, inicio)
    dados = JSON.parse(texto.to_s)
    return falhou('consulta_resposta_sem_dados', codigo: 200, inicio: inicio) unless dados.is_a?(Hash) || dados.is_a?(Array)

    Resposta.new(codigo: 200, ms: ms(inicio), dados: dados)
  rescue JSON::ParserError
    falhou('consulta_resposta_sem_dados', codigo: 200, inicio: inicio)
  end

  def falhou(motivo, codigo: nil, inicio: nil) = Resposta.new(motivo: motivo, codigo: codigo, ms: inicio && ms(inicio), dados: nil)

  def ms(inicio) = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
end
