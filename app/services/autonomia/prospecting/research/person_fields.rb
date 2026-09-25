# ESBOÇO DO CONTRATO (#679, frente B): lista fechada de campos de pessoa física. A integração troca pelo arquivo da frente B.
module Autonomia::Prospecting::Research::PersonFields
  ALLOWED = %w[name qualification entered_on].freeze

  class Violation < StandardError; end
end
