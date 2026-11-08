# A falha de uma leitura do Crm::Ai::LeitorDeMidia (#2109): de que natureza é e o que fica gravado no anexo.
#
#   definitiva (FALHAS_DEFINITIVAS), nunca relê:
#     `permanente`      a API recusou o arquivo (formato, 4xx) ou o arquivo é ilegível;
#     `sem_texto`       a leitura terminou sem texto (sem fala, arquivo grande demais, PDF escaneado);
#     `arquivo_ausente` o arquivo não chegou ao storage nem na última tentativa do job da chegada.
#   passageira (FALHAS_PASSAGEIRAS): o anexo fica pendente, com a tentativa contada (`crm_ai_midia_tentativas`) e a
#     próxima agendada (`crm_ai_midia_proxima_em`, pelas ESPERAS, nunca depois do fim da JANELA_DE_RELEITURA da mensagem).
#     Mensagem mais velha que a janela: marca `expirado`, que só uma mensagem nova na conversa relê, até
#     MAX_RELEITURAS_DO_EXPIRADO vezes; falhou em todas, vira `expirado_esgotado`, definitiva (não relê mais).
# Grava a classe do erro (`crm_ai_midia_erro`), nunca a mensagem dele: pode trazer trecho do pedido.
class Crm::Ai::FalhaDaMidia
  # Até quando (pela idade da mensagem) a falha passageira tenta de novo sozinha. Decisão do Rodrigo (23/10/2026):
  # mídia de mais de 2 dias fica de fora, salvo quando chega mensagem nova na conversa.
  JANELA_DE_RELEITURA = 48.hours
  # A espera antes de cada nova tentativa (a 1ª e a 2ª no próprio Crm::Ai::LerMidiaJob; as outras pela varredura,
  # Crm::Ai::RelerMidiaPendenteJob). Depois da última, repete a última.
  ESPERAS = [1.minute, 5.minutes, 15.minutes, 1.hour, 3.hours, 6.hours].freeze
  # O `expirado` só a mensagem nova relê; com a API fora por muito tempo, no máximo uma vez neste intervalo, por mais
  # mensagens que cheguem.
  ESPERA_DO_EXPIRADO = 1.hour
  # Quantas releituras o `expirado` tem antes de parar de vez (a credencial recusada, 401, relia uma vez por hora sem fim
  # enquanto a conversa recebia mensagem, gastando vaga do teto do dia).
  MAX_RELEITURAS_DO_EXPIRADO = 3
  # As que passam sozinhas: rede, tempo esgotado, TLS, a API ocupada ou fora (408, 429, 5xx; o ServerError do Faraday
  # inclui o TimeoutError) e a chave recusada (401: a conta troca a chave e a mídia ainda é lida; 403 é permanente). O cliente
  # da transcrição (ruby-openai) levanta o erro do Faraday pelo status; o da visão (ResponsesClient) diz o status no erro.
  FALHAS_PASSAGEIRAS = [
    *Crm::Ai::ResponsesClient::NETWORK_ERRORS, Errno::EHOSTUNREACH, Errno::ENETUNREACH, OpenSSL::SSL::SSLError,
    Faraday::ConnectionFailed, Faraday::SSLError, Faraday::ServerError, Faraday::RequestTimeoutError,
    Faraday::TooManyRequestsError, Faraday::UnauthorizedError
  ].freeze
  STATUS_DE_CREDENCIAL = [401].freeze
  # As falhas esperadas de uma leitura: as passageiras, a API da IA (o cliente da transcrição e o da visão) e o arquivo
  # ilegível. Qualquer outro erro é nosso: propaga, e o anexo fica para depois.
  FALHAS_DA_LEITURA = [
    *FALHAS_PASSAGEIRAS, Faraday::Error, OpenAI::Error,
    Crm::Ai::ResponsesClient::Error, Crm::Ai::TranscriptionClient::Error,
    ActiveStorage::IntegrityError,
    Autonomia::Agents::Knowledge::Processors::Base::ExtractionError, Autonomia::Agents::Knowledge::Processors::Base::UnsupportedFormat
  ].freeze
  FALHAS_DEFINITIVAS = %w[permanente sem_texto arquivo_ausente expirado_esgotado].freeze
  TENTATIVAS = 'crm_ai_midia_tentativas'.freeze
  PROXIMA = 'crm_ai_midia_proxima_em'.freeze
  FALHA = 'crm_ai_midia_falha'.freeze
  ERRO = 'crm_ai_midia_erro'.freeze
  RELEITURAS_DO_EXPIRADO = 'crm_ai_midia_releituras_do_expirado'.freeze

  def self.passageira?(erro)
    return erro.passageira? || STATUS_DE_CREDENCIAL.include?(erro.status) if erro.is_a?(Crm::Ai::ResponsesClient::Error)

    FALHAS_PASSAGEIRAS.any? { |classe| erro.is_a?(classe) }
  end

  # A falha passageira agendou a próxima tentativa e ela ainda não venceu.
  def self.na_espera?(meta)
    proxima = meta[PROXIMA].presence
    proxima.present? && Time.zone.parse(proxima.to_s)&.future? == true
  end

  def initialize(erro, meta:, mensagem:)
    @erro = erro
    @meta = meta
    @mensagem = mensagem
    @passageira = self.class.passageira?(erro)
  end

  def passageira? = @passageira

  def tentativa = @meta[TENTATIVAS].to_i + (@passageira ? 1 : 0)

  def expirou? = @passageira && @mensagem.created_at < JANELA_DE_RELEITURA.ago

  # Releituras do `expirado` (0 na falha que expira; cada nova falha do expirado soma 1).
  def releituras_do_expirado = @meta[FALHA] == 'expirado' ? @meta[RELEITURAS_DO_EXPIRADO].to_i + 1 : 0

  def esgotou? = expirou? && releituras_do_expirado >= MAX_RELEITURAS_DO_EXPIRADO

  # Marca o anexo como lido (sem texto): a definitiva e a passageira que expirou.
  def marca? = !@passageira || expirou?

  # O que vai para o meta do anexo marcado.
  def motivo
    return { FALHA => 'permanente', ERRO => @erro.class.name } unless @passageira

    base = { ERRO => @erro.class.name, TENTATIVAS => tentativa, RELEITURAS_DO_EXPIRADO => releituras_do_expirado }
    return base.merge(FALHA => 'expirado_esgotado') if esgotou?

    base.merge(FALHA => 'expirado', PROXIMA => ESPERA_DO_EXPIRADO.from_now.iso8601)
  end

  # O que vai para o meta do anexo que segue pendente.
  def espera
    proxima = [ESPERAS.fetch(tentativa - 1, ESPERAS.last).from_now, @mensagem.created_at + JANELA_DE_RELEITURA].min
    { TENTATIVAS => tentativa, ERRO => @erro.class.name, PROXIMA => proxima.iso8601 }
  end

  def para_o_log
    "natureza=#{@passageira ? 'passageira' : 'permanente'} tentativa=#{tentativa} expirou=#{expirou?} esgotou=#{esgotou?} erro=#{@erro.class}"
  end
end
