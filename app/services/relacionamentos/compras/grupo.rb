# O grupo de compra de uma pessoa (#3097): um só, para a lista, a ficha, as contagens e o gatilho concordarem. A mesma
# regra da tela (relacionamentos/fonte/gruposDeCompra.js, `grupoPrincipal`), na mesma ordem:
#   nunca comprou -> sem comprar há mais que `perdido_dias` -> sem comprar há mais que `em_risco_dias` -> passou da hora
#   de voltar (2 compras ou mais e sem comprar há mais que o próprio costume, com a folga) -> campeão (`campeao_compras`
#   compras ou mais e a última há até `campeao_dias`) -> comprou uma vez ou fiel.
module Relacionamentos::Compras::Grupo
  CAMPEOES = 'compra_campeoes'.freeze
  FIEIS = 'compra_fieis'.freeze
  NOVOS = 'compra_novos'.freeze
  PASSOU_DA_HORA = 'compra_passou_da_hora'.freeze
  EM_RISCO = 'compra_em_risco'.freeze
  PERDIDOS = 'compra_perdidos'.freeze
  NUNCA = 'compra_nunca'.freeze
  # Na ordem da tela: do melhor cliente para quem nunca comprou.
  TODOS = [CAMPEOES, FIEIS, NOVOS, PASSOU_DA_HORA, EM_RISCO, PERDIDOS, NUNCA].freeze
  # Os que a automação oferece: "nunca comprou" não, porque toda pessoa nova nasceria nele.
  DO_GATILHO = (TODOS - [NUNCA]).freeze

  COMPRAS_PARA_TER_RITMO = 2
  # 1,5 = passou da hora quem está sem comprar há o costume e mais a metade dele.
  FOLGA_DO_RITMO = 1.5

  module_function

  # `compra`: a linha de Relacionamentos::Compra (ou nil, quem nunca comprou). `faixas`: as da conta (Faixas.da_conta).
  def de(compra, faixas, agora = Time.current)
    return NUNCA unless compra&.quantas.to_i.positive?

    dias = (agora - compra.ultima_em) / 1.day
    sem_comprar(dias, faixas) || por_costume(compra, dias, faixas)
  end

  # Os dois "sem comprar", que valem antes de qualquer outro.
  def sem_comprar(dias, faixas)
    return PERDIDOS if dias > faixas['perdido_dias']

    EM_RISCO if dias > faixas['em_risco_dias']
  end

  def por_costume(compra, dias, faixas)
    return PASSOU_DA_HORA if passou_da_hora?(compra, dias)
    return CAMPEOES if compra.quantas >= faixas['campeao_compras'] && dias <= faixas['campeao_dias']

    compra.quantas == 1 ? NOVOS : FIEIS
  end

  def passou_da_hora?(compra, dias)
    ritmo = compra.intervalo_medio_dias
    compra.quantas >= COMPRAS_PARA_TER_RITMO && ritmo.to_f.positive? && dias > ritmo * FOLGA_DO_RITMO
  end
end
