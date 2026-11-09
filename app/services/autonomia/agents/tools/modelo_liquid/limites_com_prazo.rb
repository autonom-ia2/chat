# Os LIMITES do Liquid mais o PRAZO. O Liquid zera os contadores (`reset`, também chamado no `initialize`) no começo de
# cada render: o prazo conta dali.
class Autonomia::Agents::Tools::ModeloLiquid::LimitesComPrazo < Liquid::ResourceLimits
  def reset
    super
    @prazo = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Autonomia::Agents::Tools::ModeloLiquid.prazo_restante
  end

  def increment_render_score(amount)
    super
    conferir_prazo
  end

  def increment_write_score(output)
    super
    conferir_prazo
  end

  def conferir_prazo
    raise_limits_reached if Process.clock_gettime(Process::CLOCK_MONOTONIC) > @prazo
  end

  # O que um filtro devolve pesa o texto que carrega, dentro de listas e Hash também (revisão adversarial: a mesma lista
  # repetida por `concat` passava com poucos itens). Até TAMANHO_MAXIMO bytes e ITENS_MAXIMOS itens.
  def conferir_tamanho(valor)
    raise_limits_reached if Autonomia::Agents::Tools::ModeloLiquid.pesado?(valor)
  end
end
