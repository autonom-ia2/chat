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
  :email, :content,
  # #2469 — a pergunta do Testar do cuidado dos comentários (POST agentes_do_post/:id/testar) é texto de quem testa,
  # nunca gravado nem logado.
  :pergunta,
  # #2696 — o pedido em uma frase da Prospecção (POST searches/interpret { frase }) é texto livre de quem busca. A chave
  # é `frase`, e não `text`, que casaria também com `context` e outras.
  :frase,
  # #1479 — o "Endereço e telefone" do agente (`agent.config.atendimento`) é dado do negócio que não vai para o log.
  # `telefone` e `endereco` não casam com outro parâmetro de entrada do app hoje (conferido em 09/11).
  :telefone, :endereco,
  # #2858 F2 — o valor digitado no "Experimente" da vitrine de ferramentas prontas (CPF, CNPJ, CEP) não vai para o log.
  # O filtro casa qualquer chave que contenha "valor": num parâmetro de outro endpoint, só o log perde o número.
  :valor,
  # #2895 — o CPF da pessoa (`custom_attributes[cpf]`) e o CNPJ da empresa (`additional_attributes[cnpj]`) chegam no PATCH
  # do contato e da empresa; `documento` é o nome do campo próprio que os dois ganham na fatia seguinte. O filtro casa
  # qualquer chave que contenha "cpf", "cnpj" ou "documento": num parâmetro de outro endpoint, só o log perde o valor.
  :cpf, :cnpj, :documento,
  # #2895 — o que a pessoa digita na busca da lista de Relacionamentos (`busca`) costuma ser nome, telefone ou CPF de
  # cliente: não vai para o log. O filtro casa qualquer chave que contenha "busca"; em outro endpoint, só o log perde o texto.
  :busca,
  # #2897 — carteira de seguros: o que a pessoa corrige num seguro (PATCH relacionamentos/seguros/:id) e o PDF que ela
  # guarda são dados do cliente. O número da apólice, a seguradora e o bem (que costuma trazer a placa) não vão para o log,
  # nem o `arquivo` enviado (o log mostraria o nome do arquivo); `valor` e `busca` já saem filtrados acima. O filtro casa
  # qualquer chave que contenha "numero", "seguradora", "bem" ou "arquivo": em outro endpoint, só o log perde o valor.
  :numero, :seguradora, :bem, :arquivo
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]
