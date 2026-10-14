BaseDeClientesEval::TetoAtingido = Class.new(StandardError)
# Sem preço conhecido o gasto contaria zero e o teto nunca pararia a bateria: para também.
BaseDeClientesEval::PrecoDesconhecido = Class.new(BaseDeClientesEval::TetoAtingido)

# O cliente do Jev de produção, contando tokens e custo de cada chamada (#1246). Para antes de
# passar do teto: a chamada seguinte não sai quando o gasto chega a 95% dele.
class BaseDeClientesEval::ClienteMedido < TypesafeAi::Client
  MARGEM_DO_TETO = 0.95

  attr_reader :gasto, :chamadas, :tokens

  def initialize(teto:, **)
    super(**)
    @teto = teto
    @gasto = 0.0
    @chamadas = 0
    @tokens = 0
  end

  def evaluate(state:, questions:, model: TypesafeAi::Config.model)
    raise BaseDeClientesEval::TetoAtingido, format('gasto US$ %<gasto>.4f chegou a 95%% do teto', gasto: @gasto) if @gasto >= @teto * MARGEM_DO_TETO

    resposta = super
    registrar(resposta, model)
    resposta
  end

  private

  def registrar(resposta, modelo)
    uso = resposta['usage'].to_h
    entrada = uso['input_tokens'].to_i
    saida = uso['output_tokens'].to_i
    @chamadas += 1
    @tokens += entrada + saida
    modelo = resposta['model'].presence || modelo
    raise BaseDeClientesEval::PrecoDesconhecido, "sem preço para #{modelo}" if Crm::Ai::Pricing.rate(modelo) == Crm::Ai::Pricing::ZERO_RATE

    @gasto += Crm::Ai::Pricing.cost(model: modelo, input_tokens: entrada, output_tokens: saida)
  end
end
