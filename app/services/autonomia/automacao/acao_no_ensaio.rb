# A ação no ensaio (Ensaio, G16): o valor calculado do corpo com os dados desta conversa e o "hoje" de agora, a data que
# daria se rodasse agora. Pula como o motor: valor vazio no caminho, data que não é data, valor que não cabe no campo.
# Devolve [faria, dados], como os outros `ensaiar`; nada é chamado nem gravado.
class Autonomia::Automacao::AcaoNoEnsaio
  CALCULO = ::Autonomia::Automacao::Corpo

  def self.ensaiar(passo, valores, conta) = new(passo, valores, conta).ensaiar

  def initialize(passo, valores, conta)
    @passo = passo
    @valores = valores
    @conta = conta
  end

  def ensaiar
    corpo = @passo['corpo'].to_h
    return ['faltou_valor'] if caminho_vazio?
    return ['acao'] unless CALCULO.calculado_em?(corpo)

    montado = CALCULO.new(corpo, valores: @valores, conta: @conta).montar
    return [montado.motivo] if montado.motivo
    return ['valor_fora_do_formato'] if ::Autonomia::Automacao::CampoDaAcao.problemas(@passo['acao'], corpo, montado.corpo, conta: @conta).any?

    ['acao', { calculados: calculados(corpo, montado.corpo) }]
  end

  private

  # Como o motor: um valor vazio no caminho da ação pula o passo.
  def caminho_vazio?
    @passo['caminho'].to_h.values.any? { |valor| valor.is_a?(Hash) && @valores.ler(valor['$valor']).blank? }
  end

  def calculados(corpo, montado)
    CALCULO.lugares(corpo).map do |onde, _folha|
      { campo: onde.reverse.find { |parte| parte.is_a?(String) }, valor: montado.dig(*onde) }
    end
  end
end
