# ESBOÇO DO CONTRATO (#679, frente B). A integração troca pelo arquivo da frente B.
Autonomia::Prospecting::Research::Registry::Company = Struct.new(
  :cnpj, :legal_name, :trade_name, :registration_status, :registration_state, :legal_nature_code, :legal_nature_text,
  :opened_on, :cnae, :sources, :qsa,
  keyword_init: true
)
