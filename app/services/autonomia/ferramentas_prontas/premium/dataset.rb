# UM DATASET DA BIGDATACORP (#2858, F7): o que a BigDataCorp cobra e o que a F7 repassa. Os nomes, as rotas e o custo
# vêm da documentação pública (docs.bigdatacorp.com.br, 1ª faixa, até 10 mil consultas por mês, lida em 11/11/2026).
#
# `nome`: o dataset no corpo do pedido. `rota`: `/empresas`, `/pessoas`, `/veiculos`, `/enderecos`, `/ondemand` ou
#   `/marketplace`. `resposta`: a chave do dataset em `Result[0]`.
# `custo`: o que a BigDataCorp cobra de nós. `preco`: o do plano aprovado (custo × 1,5), o que vai à fatura.
# `busca`: os parâmetros já normalizados -> o `q` da BigDataCorp (`doc{...}`, `licenseplate{...}`). Só dígito, letra
#   maiúscula e o que o `Parametro` aceitou entram nele.
# `extrair`: o dado da BigDataCorp -> só o que o agente precisa (nada de nome de parente, sócio pessoa física, link de
#   arquivo nem PDF). Devolve nil quando não sobrou nada: sem registro.
# `prazo`: o teto da chamada. As consultas sob demanda (`/ondemand`) buscam na fonte oficial na hora, e a documentação
#   mostra 30 a 40 segundos; as da base, segundos.
# `cobra_sem_registro`: a BigDataCorp cobra a consulta que volta vazia? Só a vistoria não cobra (doc da Rede Vistorias).
class Autonomia::FerramentasProntas::Premium::Dataset
  PRAZO_DA_BASE = 20
  PRAZO_SOB_DEMANDA = 55
  ROTA_SOB_DEMANDA = '/ondemand'.freeze
  MARGEM = BigDecimal('1.5')

  attr_reader :nome, :rota, :resposta, :custo, :preco, :busca, :extrair, :prazo

  def initialize(nome:, rota:, resposta:, custo:, preco:, busca:, extrair:, prazo: nil, cobra_sem_registro: true) # rubocop:disable Metrics/ParameterLists
    @nome = nome
    @rota = rota
    @resposta = resposta
    @custo = BigDecimal(custo)
    @preco = BigDecimal(preco)
    @busca = busca
    @extrair = extrair
    @prazo = prazo || (rota == ROTA_SOB_DEMANDA ? PRAZO_SOB_DEMANDA : PRAZO_DA_BASE)
    @cobra_sem_registro = cobra_sem_registro
  end

  # O que a BigDataCorp nos cobra por esta consulta, pelo resultado.
  def custo_de(resultado)
    return BigDecimal(0) if resultado == 'falha'
    return BigDecimal(0) if resultado == 'sem_registro' && !@cobra_sem_registro

    custo
  end

  def preco_confere?
    (custo * MARGEM).round(4) == preco
  end
end
