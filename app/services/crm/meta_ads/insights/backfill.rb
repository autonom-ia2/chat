# Primeira carga de 90 dias (#1073, CA-2.4), por relatório assíncrono da Meta: pede o relatório, espera ficar
# pronto e lê as linhas. Dois relatórios, um depois do outro: por anúncio (`ads`) e por posicionamento
# (`placements`). Quem espera e repete é o Crm::MetaAds::InsightsBackfillJob; aqui ficam as chamadas.
#
# Uma carga por conexão de cada vez: a marca RUNNING_KEY dura até a carga terminar ou RUNNING_TTL passar.
class Crm::MetaAds::Insights::Backfill
  KINDS = %w[ads placements].freeze
  RUNNING_KEY = 'crm:meta_ads:insights:backfill'.freeze
  RUNNING_TTL = 2.hours
  COMPLETED = 'Job Completed'.freeze
  FAILED = ['Job Failed', 'Job Skipped'].freeze

  def self.claim(connection_id)
    Redis::Alfred.set("#{RUNNING_KEY}:#{connection_id}", 1, nx: true, ex: RUNNING_TTL.to_i) ? true : false
  end

  def self.release(connection_id)
    Redis::Alfred.delete("#{RUNNING_KEY}:#{connection_id}")
  end

  def initialize(connection, kind)
    raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind)

    @connection = connection
    @kind = kind
  end

  def readable?
    @connection.insights_readable? && !Crm::MetaAds::Insights::Usage.paused?(@connection.ad_account_id)
  end

  # ID do relatório, ou nil quando a Meta recusou (o motivo já foi tratado por Failure).
  def start
    result = client.start_insights_report(@connection.ad_account_id, query)
    return fail_with(result) unless result.ok

    result.data.to_h['report_run_id'].presence
  end

  # :running, :completed ou :failed
  def status(report_run_id)
    result = client.insights_report_status(report_run_id)
    unless result.ok
      fail_with(result)
      return :failed
    end

    state = result.data.to_h['async_status'].to_s
    return :completed if state == COMPLETED
    return :failed if FAILED.include?(state)

    :running
  end

  # Lê e grava todas as páginas. true quando leu até o fim.
  def read!(report_run_id)
    result = client.each_report_page(report_run_id) { |rows| write(rows) }
    return true if result.ok

    fail_with(result)
    false
  end

  private

  def query
    preset = Crm::MetaAds::Insights::Query::BACKFILL
    @kind == 'ads' ? Crm::MetaAds::Insights::Query.ads(preset) : Crm::MetaAds::Insights::Query.placements(preset)
  end

  def write(rows)
    @kind == 'ads' ? writer.ads!(rows) : writer.placements!(rows)
  end

  def fail_with(result)
    outcome = Crm::MetaAds::Insights::Failure.handle!(@connection, result)
    Rails.logger.warn("[MetaAdsInsights] backfill #{@kind} act_#{@connection.ad_account_id} #{outcome}")
    nil
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def writer
    @writer ||= Crm::MetaAds::Insights::Writer.new(@connection)
  end
end
