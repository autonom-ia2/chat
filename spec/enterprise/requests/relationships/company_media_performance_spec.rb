require 'rails_helper'

RSpec.describe 'Company media bounded query performance', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/companies/#{company.id}/media" }
  # Diagnóstico (#2955): este exemplo dá 500 de vez em quando na CI. Uma consulta é cancelada pelo statement_timeout, o
  # app trata como 422 (handle_with_exception, em nível info) e, como o exemplo vive numa transação só, os after_action
  # rodam em cima da transação abortada. Falta saber por que a consulta trava; a falha passa a dizer.
  let(:anotado) { {} }

  before { anotado[:pid] = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()') }

  around do |exemplo|
    assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      erro = args.last[:exception]
      anotado[:erro] ||= "#{erro.first} em #{args.last[:name].inspect}" if erro
    end
    vigia = Thread.new(anotado) { |notas| vigiar_consulta_lenta(notas) }
    exemplo.run
  ensure
    anotado[:fim] = true
    vigia&.join
    ActiveSupport::Notifications.unsubscribe(assinatura)
  end

  def banco_por_fora
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect({ host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
                 password: config[:password] }.compact)
  end

  # Olha de fora da transação do teste, a cada segundo: a consulta do teste que roda há mais de 3 s, o que ela espera e
  # quem a segura (pg_blocking_pids). Sem espera e sem quem segure, é consulta lenta de verdade.
  def vigiar_consulta_lenta(notas)
    conexao = banco_por_fora
    until notas[:fim]
      notas[:lenta] ||= amostra(conexao, notas[:pid])
      sleep 1
    end
  rescue PG::Error => e
    notas[:lenta] ||= ["o vigia ficou sem banco: #{e.class}"]
  ensure
    conexao&.close
  end

  # nil enquanto nenhuma consulta do teste passa de 3 s.
  def amostra(conexao, pid)
    return if pid.nil?

    conexao.exec_params(consulta_lenta, [pid]).values.map { |linha| linha.join(' | ') }.presence
  end

  # papel | pid | tipo | espera | evento | quem segura (ou estado) | há quanto tempo | consulta
  def consulta_lenta
    <<~SQL.squish
      WITH lenta AS (
        SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid) AS quem_segura, query, now() - query_start AS ha
        FROM pg_stat_activity
        WHERE pid = $1 AND state = 'active' AND now() - query_start > interval '3 seconds'
      )
      SELECT 'lenta', l.pid, 'client backend', l.wait_event_type, l.wait_event, l.quem_segura::text, l.ha::text, left(l.query, 200)
      FROM lenta l
      UNION ALL
      SELECT 'segura', a.pid, a.backend_type, a.wait_event_type, a.wait_event, a.state, (now() - a.xact_start)::text, left(a.query, 200)
      FROM pg_stat_activity a JOIN lenta l ON a.pid = ANY (l.quem_segura)
    SQL
  end

  def diagnostico
    "status #{response.status}; primeiro erro de SQL: #{anotado[:erro] || 'nenhum'}; " \
      "consulta parada há mais de 3 s: #{(anotado[:lenta] || ['nenhuma']).join(' || ')}"
  end

  it 'searches 1,000 occurrences without per-row queries and meets the predeclared local p95 target' do
    account.enable_features!('companies', 'relationships_company_media')
    inbox = create(:inbox, account: account)
    messages = Array.new(50) do
      contact = create(:contact, account: account, company: company)
      conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
      create(:message, account: account, conversation: conversation, inbox: inbox, sender: contact)
    end
    blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/sample.pdf').open,
                                                  filename: 'Synthetic benchmark.pdf', content_type: 'application/pdf')
    rows = Array.new(1000) do |index|
      { account_id: account.id, message_id: messages[index % messages.length].id, file_type: Attachment.file_types.fetch('file'),
        created_at: Time.current - index.seconds, updated_at: Time.current }
    end
    rows.each { |row| Attachment.create!(row.merge(file: blob)) }

    metrics = {}
    excluded_queries = %w[SCHEMA TRANSACTION]
    [25, 50].each do |page_size|
      # Warm route/autoloading outside the timed samples; no conversion belongs to this endpoint.
      get url, headers: headers, params: { per_page: page_size, q: 'Synthetic', group: 'contact' }
      durations = []
      query_counts = []
      20.times do
        count = 0
        listener = lambda do |*args|
          payload = args.last
          count += 1 unless payload[:cached] || excluded_queries.include?(payload[:name])
        end
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
          get url, headers: headers, params: { per_page: page_size, q: 'Synthetic', group: 'contact' }
        end
        durations << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000)
        query_counts << count
        expect(response).to have_http_status(:ok), diagnostico
        expect(response.parsed_body['meta']['total']).to eq(1000)
        expect(response.parsed_body['payload'].length).to eq(page_size)
      end
      metrics[page_size] = { p95_ms: durations.sort[18].round(2), max_queries: query_counts.max, samples: durations.length }
    end
    expect(metrics[50][:max_queries] - metrics[25][:max_queries]).to be <= 2
    # Wall-clock time depends on the CI machine's load, so the p95 target is only enforced on demand
    # (RUN_PERF=1); the query-count bound above is what proves the search has no per-row queries.
    expect(metrics.values.map { |value| value[:p95_ms] }.max).to be < 500 if ENV['RUN_PERF'] == '1'
    expect(Relationships::CompanyPreviewJob).not_to have_been_enqueued
    puts "RELATIONSHIPS_PERFORMANCE #{metrics.to_json}"
  end
end
