# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes,
  :phone, :phone_number, :raw_phone, :normalized_phone,
  :code, :state, :signed_request, :error_description, :fb_dtsg, :lsd, :cookie, :session_json, :ticket,
  # O que a pessoa digita na busca da Central (#977) pode trazer dado de cliente: não vai para o log.
  :termo,
  # Aviso de clique das páginas (#1011): formulário do cliente (lead, lead_form, lead_data) e
  # sinais da Meta. O Middleware::TrackedLinkSignalGuard já impede o corpo de virar params;
  # isto cobre qualquer outro caminho que traga essas chaves.
  :lead, :fbc, :fbp, :page_url,
  # #1427 — as fotos do Testar do agente (data-url em base64, `images` do POST /agents/:id/test) não vão para o log do
  # Rails. O filtro casa qualquer chave que contenha "images"; hoje só esse endpoint recebe uma. O Sentry lê o corpo
  # JSON cru e não passa por aqui: lá quem tira as fotos é o SentryHttpAuthScrubber.
  :images,
  # #2103 — o log do Rails vai para o CloudWatch por 30 dias. E-mail e texto de mensagem (`content`) de cliente
  # não vão junto; telefone já sai filtrado acima.
  :email, :content
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]
