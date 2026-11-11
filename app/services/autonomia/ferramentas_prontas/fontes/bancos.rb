# BANCOS (#2858, F1): o nome do banco pelo código de compensação (o "341" do boleto e da transferência).
#   - principal: BrasilAPI; reserva: a lista oficial de participantes do STR do Banco Central (CSV público).
# Termos: BrasilAPI pede uso com "natureza de uma pessoa real"; o CSV do Banco Central é dado aberto. Cache de 30 dias.
module Autonomia::FerramentasProntas::Fontes::Bancos
  Parametro = Autonomia::FerramentasProntas::Parametro

  module_function

  def banco(codigo:, nome:, nome_completo:, ispb:)
    { 'codigo' => codigo, 'nome' => nome, 'nome_completo' => nome_completo, 'ispb' => ispb }.compact
  end

  # "341", "1", "001" -> "341", "001", "001".
  CODIGO = Parametro.new(nome: 'codigo', descricao: 'O código do banco, de 1 a 3 dígitos (ex.: 341).',
                         deduza: 'o código tem de 1 a 3 dígitos.') do |valor|
    texto = valor.to_s.strip
    texto.rjust(3, '0') if texto.present? && texto.length <= 3 && texto.delete(Parametro::DIGITOS).empty?
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'bancos', slug: 'pronta_bancos', nome: 'Bancos', flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'O nome do banco pelo código de compensação (ex.: 341).',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'banco', descricao: 'o banco do código', obrigatorios: [CODIGO], provedores: [BrasilApi, Str],
        validade: 30.days, prazo_por_fonte: 3, prazo_total: 6
      )
    ],
    limite_diario: 500,
    termos: 'BrasilAPI (uso de pessoa real) e a lista do STR do Banco Central (dado aberto) de reserva. Cache de 30 dias.'
  )
end
