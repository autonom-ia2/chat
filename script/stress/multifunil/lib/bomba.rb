# A "bomba" de jobs: o ambiente roda com o adaptador :test do ActiveJob, então nada roda sozinho. A bomba executa, na
# ordem do horário agendado e com o relógio virtual avançando até ele, só os jobs do coração do multifunil:
#   - EventDispatcherJob: entregue SÓ ao Crm::ConversationObserverListener (webhook, notificação, automação etc. ficam de
#     fora do teste);
#   - Crm::SyncConversationCardJob, Crm::Subjects::IdentifyJob, Crm::Ai::EvaluateCardJob e, na Fase B, Crm::Ai::EvaluateCardsJob.
# Todo o resto é descartado e contado (aparece no relatório), para nada sumir em silêncio.
class Stress::Bomba
  # Crm::Ai::EvaluateCardsJob: a avaliação conjunta do PR #1700 (Fase B); na Fase A ela não existe.
  EXECUTA = %w[Crm::SyncConversationCardJob Crm::Subjects::IdentifyJob Crm::Ai::EvaluateCardJob Crm::Ai::EvaluateCardsJob].freeze
  CRONOMETRO = { 'Crm::Subjects::IdentifyJob' => 'assunto', 'Crm::Ai::EvaluateCardJob' => 'movimentacao',
                 'Crm::Ai::EvaluateCardsJob' => 'movimentacao' }.freeze
  MAX_EXECUCOES = 400
  MAX_REPETICOES_DO_MESMO_JOB = 3

  attr_reader :descartados, :erros

  def initialize(relogio:, segredos:)
    @relogio = relogio
    @segredos = segredos
    @descartados = Hash.new(0)
    @erros = []
    @latencia = Hash.new(0.0)
    @repeticoes = Hash.new(0)
  end

  def limpar!
    fila.clear
  end

  # Executa até a fila esvaziar. Jobs agendados para depois do teto (follow-up de horas, por exemplo) são descartados.
  def drenar(teto_segundos: 900)
    limite = @relogio.agora + teto_segundos.seconds
    MAX_EXECUCOES.times do
      break if fila.empty?

      entrada = proxima
      momento = entrada[:at] ? Time.zone.at(entrada[:at]) : nil
      next perder(entrada[:job].to_s, 'agendado depois do teto') if momento && momento > limite

      @relogio.ir_para(momento) if momento
      executar(entrada)
    end
    raise 'bomba: fila não esvaziou (laço de jobs?)' unless fila.empty?
  end

  # Segundos reais gastos em cada IA desde a última leitura (zera ao ler).
  def latencia!
    lido = @latencia.dup
    @latencia.clear
    lido
  end

  private

  def fila
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def proxima
    indice = fila.each_index.min_by { |i| [fila[i][:at] || 0, i] }
    fila.delete_at(indice)
  end

  def executar(entrada)
    nome = entrada[:job].to_s
    return despachar_ao_crm(entrada) if nome == 'EventDispatcherJob'
    return @descartados[nome] += 1 unless EXECUTA.include?(nome)

    chave = entrada['job_id']
    @repeticoes[chave] += 1
    return perder(nome, 'retry excedido') if @repeticoes[chave] > MAX_REPETICOES_DO_MESMO_JOB

    cronometrar(nome) { ActiveJob::Base.execute(entrada) }
  rescue StandardError => e
    @erros << { job: nome, erro: e.class.name, mensagem: limpo(e.message) }
  end

  def cronometrar(nome)
    comeco = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    ia = CRONOMETRO[nome]
    @latencia[ia] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - comeco if ia
  end

  def despachar_ao_crm(entrada)
    job = ActiveJob::Base.deserialize(entrada)
    job.send(:deserialize_arguments_if_needed)
    nome_evento, momento, dados = job.arguments
    evento = Events::Base.new(nome_evento, momento, dados)
    ouvinte = Crm::ConversationObserverListener.instance
    return @descartados["evento sem ouvinte do CRM: #{evento.method_name}"] += 1 unless ouvinte.respond_to?(evento.method_name)

    ouvinte.public_send(evento.method_name, evento)
  end

  # Job do coração do multifunil que não rodou é erro (a conversa FALHA); qualquer outro só é contado.
  def perder(nome, motivo)
    return @descartados["#{nome} (#{motivo})"] += 1 unless EXECUTA.include?(nome) || nome == 'EventDispatcherJob'

    @erros << { job: nome, erro: 'nao_rodou', mensagem: motivo }
  end

  # Nenhuma mensagem de erro sai com o valor de um segredo (comparação exata de texto, sem regex).
  def limpo(texto)
    redigido = @segredos.reduce(texto.to_s) { |acc, segredo| segredo.present? ? acc.gsub(segredo, '<REDACTED>') : acc }
    redigido.first(300)
  end
end
