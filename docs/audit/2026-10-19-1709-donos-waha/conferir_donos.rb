# Conferência dos donos do token nas caixas WAHA (chat#1709). SÓ LEITURA.
# Roda dentro do chatwoot-web (bundle exec ruby), sem subir o Rails:
# - banco em transação READ ONLY;
# - motor só com GET /api/apps?session=<sessão>;
# - nenhum token é impresso: só os 16 primeiros caracteres do sha256.
require 'pg'
require 'json'
require 'net/http'
require 'digest'

OWNER_KEY = 'account_token_owner_user_id'.freeze
TIMEOUT = 15

# Motor (esquema + host) e sessão da caixa. A sessão vem gravada na caixa; nas antigas, do caminho do webhook
# (/webhooks/chatwoot/<sessão>/<app>).
def engine_and_session(webhook_url, attributes)
  uri = URI(webhook_url.to_s)
  session = attributes['session'].to_s
  session = uri.path.to_s.split('/').reject(&:empty?)[2].to_s if session.empty?
  ["#{uri.scheme}://#{uri.host}", session]
rescue URI::InvalidURIError
  [nil, attributes['session'].to_s]
end

def chatwoot_apps(engine, session, api_key)
  uri = URI("#{engine}/api/apps")
  uri.query = URI.encode_www_form(session: session)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
    request = Net::HTTP::Get.new(uri)
    request['X-Api-Key'] = api_key
    http.request(request)
  end
  return [:erro, "http_#{response.code}"] unless response.code.to_i == 200

  apps = JSON.parse(response.body)
  [:ok, Array(apps).select { |app| app.is_a?(Hash) && app['app'] == 'chatwoot' }]
rescue StandardError => e
  [:erro, e.class.name]
end

db = PG.connect(ENV.fetch('DATABASE_URL'))
db.exec('BEGIN TRANSACTION READ ONLY')
api_key = ENV.fetch('WAHA_API_KEY', '')
known_engine = begin
  u = URI(ENV.fetch('WAHA_API_URL', ''))
  "#{u.scheme}://#{u.host}"
rescue StandardError
  nil
end

inboxes = db.exec(<<~SQL)
  SELECT i.account_id, i.id AS inbox_id, c.id AS channel_api_id, c.webhook_url, c.additional_attributes::text AS attrs,
         (coalesce(c.secret, '') <> '') AS tem_secret
  FROM inboxes i
  JOIN channel_api c ON c.id = i.channel_id AND i.channel_type = 'Channel::Api'
  WHERE c.additional_attributes->>'provider' = 'waha'
  ORDER BY i.account_id, i.id
SQL

puts %w[conta caixa canal sessao motor secret dono_gravado app_confere hash16 token_de membro papel veredito].join(' | ')
inboxes.each do |row|
  attributes = JSON.parse(row['attrs'].to_s)
  attributes = JSON.parse(attributes) if attributes.is_a?(String)
  engine, session = engine_and_session(row['webhook_url'], attributes)
  recorded = attributes[OWNER_KEY].to_s
  base = [row['account_id'], row['inbox_id'], row['channel_api_id'], session, engine.to_s.sub('https://', ''), row['tem_secret'], recorded.empty? ? '-' : recorded]

  if engine != known_engine || session.to_s.empty?
    puts (base + ['-', '-', '-', '-', '-', 'NAO_CONFERIDA (motor de outra stack ou sem sessao)']).join(' | ')
    next
  end

  status, apps = chatwoot_apps(engine, session, api_key)
  if status == :erro
    puts (base + ['-', '-', '-', '-', '-', "NAO_CONFERIDA (motor: #{apps})"]).join(' | ')
    next
  end

  app = apps.find { |a| a.dig('config', 'inboxId').to_s == row['inbox_id'] }
  if app.nil?
    puts (base + ["apps=#{apps.size} nenhum desta caixa", '-', '-', '-', '-', 'NAO_GRAVAR (sem app chatwoot desta caixa)']).join(' | ')
    next
  end

  confere = app.dig('config', 'accountId').to_s == row['account_id'] ? 'sim' : 'CONTA_DIFERENTE'
  digest = Digest::SHA256.hexdigest(app.dig('config', 'accountToken').to_s)
  match = db.exec_params(<<~SQL, [digest, row['account_id']])
    SELECT t.owner_type, t.owner_id,
           (au.id IS NOT NULL) AS membro, au.role
    FROM access_tokens t
    LEFT JOIN account_users au ON t.owner_type = 'User' AND au.user_id = t.owner_id AND au.account_id = $2::bigint
    WHERE encode(sha256(t.token::bytea), 'hex') = $1
  SQL

  if match.ntuples != 1
    puts (base + [confere, digest[0, 16], "#{match.ntuples} tokens", '-', '-', 'NAO_GRAVAR (token nao casa com 1 registro)']).join(' | ')
    next
  end

  m = match[0]
  owner = "#{m['owner_type']}##{m['owner_id']}"
  verdict =
    if confere != 'sim' then 'NAO_GRAVAR (app de outra conta)'
    elsif m['owner_type'] != 'User' then "NAO_GRAVAR (token de #{m['owner_type']})"
    elsif m['membro'] != 't' then 'NAO_GRAVAR (dono do token nao e membro da conta)'
    elsif recorded.empty? then "GRAVAR #{m['owner_id']}"
    elsif recorded == m['owner_id'] then 'OK (gravado confere)'
    else "DIVERGE (gravado #{recorded}, token de #{m['owner_id']})"
    end
  role = { '0' => 'agente', '1' => 'administrador' }.fetch(m['role'].to_s, m['role'].to_s)
  puts (base + [confere, digest[0, 16], owner, m['membro'] == 't' ? 'sim' : 'nao', role, verdict]).join(' | ')
end

db.exec('ROLLBACK')
