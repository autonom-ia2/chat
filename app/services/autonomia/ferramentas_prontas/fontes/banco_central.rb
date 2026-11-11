# BANCO CENTRAL (#2858, F1): os números oficiais do dia num card só. O agente escolhe a consulta pelo sentido:
#   - selic: a meta da Selic definida pelo Copom (SGS 432); reserva: BrasilAPI (taxas);
#   - ipca: a inflação oficial do último mês e a dos últimos 12 meses (SGS 433 e 13522); reserva: BrasilAPI (só os 12
#     meses);
#   - dolar: a cotação PTAX do dólar, compra e venda, do último boletim (Olinda/PTAX); reserva: SGS 1 e 10813;
#   - focus: a mediana do Boletim Focus (expectativa do mercado) para o ano e o seguinte. Só o Banco Central publica:
#     sem reserva, e com a fonte fora o agente ouve "não consegui".
# Termos: dados abertos do Banco Central, sem chave; sem limite publicado. Cache de 1 hora no dólar e de 6 horas no
# resto (a série muda no máximo uma vez por dia útil).
module Autonomia::FerramentasProntas::Fontes::BancoCentral
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  # indicador -> o nome no Focus.
  INDICADORES = { 'ipca' => 'IPCA', 'selic' => 'Selic', 'cambio' => 'Câmbio', 'pib' => 'PIB Total' }.freeze
  # A unidade da mediana do Focus em cada indicador: a variação do IPCA e do PIB no ano, a Selic ao ano e o dólar em reais.
  # A taxa ao ano vai em código (`percentual_ao_ano`), não em texto: a tela traduz a unidade para o idioma dela, e o
  # agente lê o código igual (varredura P10: "ao ano" aparecia na tela em inglês).
  AO_ANO = 'percentual_ao_ano'.freeze
  UNIDADES_DO_FOCUS = { 'ipca' => '%', 'selic' => AO_ANO, 'cambio' => 'R$', 'pib' => '%' }.freeze

  module_function

  # "13.75" -> 13.75; nil quando não é número.
  def numero(valor)
    return valor.to_f if valor.is_a?(Numeric)

    texto = valor.to_s.strip
    Float(texto, exception: false) if texto.present? && texto.delete('0-9.-').empty?
  end

  def selic(valor)
    { 'indicador' => 'Selic (meta do Copom)', 'valor' => valor, 'unidade' => AO_ANO }
  end

  # "10/2026" (o mês do SGS) -> "2026-10": a tela formata o mês no idioma dela (varredura P10).
  def mes_iso(mes_e_ano)
    mes, ano = mes_e_ano.to_s.split('/')
    ano && mes ? "#{ano}-#{mes}" : mes_e_ano
  end

  def ipca(mes:, no_mes:, em_12_meses:)
    { 'indicador' => 'IPCA', 'mes_de_referencia' => mes, 'variacao_no_mes' => no_mes, 'acumulado_12_meses' => em_12_meses,
      'unidade' => '%' }.compact
  end

  def dolar(compra:, venda:, data:)
    { 'indicador' => 'Dólar PTAX (Banco Central)', 'compra' => compra, 'venda' => venda, 'data' => data, 'unidade' => 'R$' }
  end

  INDICADOR = Parametro.new(nome: 'indicador', descricao: 'Na consulta focus: qual expectativa.', opcoes: INDICADORES.keys,
                            deduza: 'escolha da lista o indicador do que o cliente perguntou.')

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'banco_central', slug: 'pronta_banco_central', nome: 'Banco Central',
    flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'Os números oficiais do Banco Central: Selic, IPCA, dólar (PTAX) e a expectativa do mercado (Focus).',
    consultas: [
      Consulta.new(nome: 'selic', descricao: 'a meta da Selic hoje', provedores: [Sgs, BrasilApi], validade: 6.hours,
                   prazo_por_fonte: 3, prazo_total: 6),
      Consulta.new(nome: 'ipca', descricao: 'a inflação oficial do último mês e de 12 meses', provedores: [Sgs, BrasilApi],
                   validade: 6.hours, prazo_por_fonte: 3, prazo_total: 6),
      Consulta.new(nome: 'dolar', descricao: 'a cotação oficial do dólar (PTAX)', provedores: [Ptax, Sgs],
                   validade: 1.hour, prazo_por_fonte: 3, prazo_total: 6),
      Consulta.new(nome: 'focus', descricao: 'a expectativa do mercado (Boletim Focus); pede indicador',
                   obrigatorios: [INDICADOR], provedores: [Focus], validade: 6.hours, prazo_por_fonte: 4, prazo_total: 4)
    ],
    limite_diario: 500,
    termos: 'Dados abertos do Banco Central (SGS, Olinda), sem chave e sem limite publicado; BrasilAPI de reserva. ' \
            'Cache de 1 a 6 horas.'
  )
end
