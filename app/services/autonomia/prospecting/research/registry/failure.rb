# Nenhuma fonte trouxe cadastro válido. reason: :invalid_cnpj, :providers_exhausted ou :deadline_exceeded.
# attempts é a auditoria de cada tentativa, sem corpo de resposta e sem mensagem de erro.
Autonomia::Prospecting::Research::Registry::Failure = Data.define(:cnpj, :reason, :attempts) do
  def failed? = true
end
