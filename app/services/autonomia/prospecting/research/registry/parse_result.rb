# Saída de um parser: a empresa quando o cadastro é válido, ou o motivo semântico da recusa (o mesmo código do Orth).
Autonomia::Prospecting::Research::Registry::ParseResult = Data.define(:company, :reason, :qsa_state) do
  def valid? = reason.nil?
end
