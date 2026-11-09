# G42 (#2721): a leitura do "resumir" com o que a execução tentou (EnviosDaExecucao) junto da conversa do alvo. Vazia
# só quando não há nada nas duas.
class Autonomia::Automacao::LeituraDaExecucao < SimpleDelegator
  def initialize(leitura, envios)
    super(leitura)
    @envios = envios
  end

  def conversa = __getobj__.conversa.merge(@envios.dados)

  def vazio? = __getobj__.vazio? && @envios.dados.empty?
end
