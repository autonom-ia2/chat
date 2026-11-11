# O TOKEN DA BIGDATACORP NO PROCESSO, entre as consultas Premium (#2858, F7): a consulta seguinte não gera outro enquanto
# ele não vence. Só em memória, nunca em log nem inspect (o `Token` do cliente esconde o valor). Mutex: duas threads do
# mesmo worker não leem um token pela metade. O cliente da BigDataCorp usa pela opção `token_cache` (`read`/`write`).
class Autonomia::FerramentasProntas::Premium::Tokens
  def initialize
    @mutex = Mutex.new
    @token = nil
  end

  def read
    @mutex.synchronize { @token }
  end

  def write(token)
    @mutex.synchronize { @token = token }
  end

  def inspect = "#<#{self.class.name} [REDACTED]>"
  alias to_s inspect
end
