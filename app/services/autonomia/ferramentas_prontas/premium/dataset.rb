# UM DATASET DA BIGDATACORP (#2858, F7): o que a BigDataCorp cobra e o que a F7 repassa. Os nomes, as rotas e o custo
# vêm da documentação pública (docs.bigdatacorp.com.br, 1ª faixa, até 10 mil consultas por mês, lida em 11/11/2026).
#
# `nome`: o dataset no corpo do pedido. `rota`: `/empresas`, `/pessoas`, `/veiculos`, `/enderecos`, `/ondemand` ou
#   `/marketplace`. `resposta`: a chave do dataset em `Result[0]`.
# `custo`: o que a BigDataCorp cobra de nós. `preco`: o do plano aprovado, o que vai à fatura: custo × 1,5, arredondado
#   para cima ao centavo (o embargo do IBAMA, R$ 0,225, é R$ 0,23; decisão do Rodrigo, 11/11).
# `busca`: os parâmetros já normalizados -> o `q` da BigDataCorp (`doc{...}`, `licenseplate{...}`). Só dígito, letra
#   maiúscula e o que o `Parametro` aceitou entram nele.
# `extrair`: o dado da BigDataCorp -> só o que o agente precisa (nada de nome de parente, sócio pessoa física, link de
#   arquivo nem PDF). Devolve nil quando não sobrou nada: sem registro.
# `prazo`: o teto da chamada. As consultas sob demanda (`/ondemand`) buscam na fonte oficial na hora, e a documentação
#   mostra 30 a 40 segundos; as da base, segundos. Algumas da base são lentas de verdade (`PRAZO_DAS_LENTAS`): no teste
#   direto na API (12/11/2026), `processes` levou 36 s e `companies_statistics` 81 s, e o prazo da base (20 s) cortava
#   as duas. Decisão do Rodrigo (#2946): 120 s para elas, "é processo longo mesmo".
# `cobra_sem_registro`: a BigDataCorp cobra a consulta que volta vazia? Só a vistoria não cobra (doc da Rede Vistorias).
# `forma`: o que vem em `Result[0][resposta]`. As consultas sob demanda (`OnlineCertificates`, `OnlineQuery`) mandam uma
#   lista; as da base, um objeto. A `Leitura` confere a forma antes de extrair: forma errada é a BigDataCorp que mudou.
class Autonomia::FerramentasProntas::Premium::Dataset
  RESPOSTAS_EM_LISTA = %w[OnlineCertificates OnlineQuery].freeze
  PRAZO_DA_BASE = 20
  PRAZO_SOB_DEMANDA = 55
  PRAZO_DAS_LENTAS = 120
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

  # O que a BigDataCorp nos cobra por esta consulta, pelo resultado. A falha não custa, salvo quando o pedido já tinha
  # saído (`custo_possivel`: a resposta que não lemos, o tempo esgotado com o pedido no ar, a entrega incerta): aí a
  # BigDataCorp pode ter cobrado, e o custo fica na telemetria para bater com o painel dela (aceite 11), sem contar para
  # o cliente. A fonte lenta (DATASET IS TOO SLOW) e o 504 não custam. O documento inválido (-114/-155) custa cheio. A
  # fonte dessas regras: "Regras de contabilização de consulta" da BigDataCorp, citada em
  # `docs/ferramentas-prontas/termos-das-fontes.md` (seção Premium).
  def custo_de(resultado, custo_possivel: false)
    return custo_possivel ? custo : BigDecimal(0) if resultado == 'falha'
    return BigDecimal(0) if resultado == 'sem_registro' && !@cobra_sem_registro

    custo
  end

  def forma
    RESPOSTAS_EM_LISTA.include?(resposta) ? Array : Hash
  end

  def preco_confere?
    (custo * MARGEM).round(2, BigDecimal::ROUND_CEILING) == preco
  end
end
