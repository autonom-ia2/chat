# Resultado da busca de um CNPJ na cadeia de fontes: a empresa (quando alguma fonte serviu) e as tentativas.
Autonomia::Prospecting::Research::Registry::Hydration = Data.define(:cnpj, :company, :failure_reason, :attempts) do
  def result
    company || Autonomia::Prospecting::Research::Registry::Failure.new(cnpj: cnpj, reason: failure_reason, attempts: attempts)
  end
end
