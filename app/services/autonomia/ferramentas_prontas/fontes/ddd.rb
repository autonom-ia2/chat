# DDD (#2858, F1): o estado e as cidades de um código de área.
#   - principal: BrasilAPI (estado e cidades, da Anatel);
#   - reserva: o plano de numeração calculado aqui (`ddd/plano.rb`), sem rede: o estado de cada DDD, que é fixo. Sem
#     as cidades, e a resposta diz isso.
# Regra "QI 70": o parâmetro aceita o telefone inteiro ("34 99999-0000", "+55 34 ...") e fica só com o DDD aqui; só o
# DDD vai à fonte, nunca o telefone. Termos: BrasilAPI pede uso com "natureza de uma pessoa real". Cache de 30 dias.
module Autonomia::FerramentasProntas::Fontes::Ddd
  Parametro = Autonomia::FerramentasProntas::Parametro

  MAX_CIDADES = 200
  PAIS = '55'.freeze
  # O 0 da ligação de longa distância ("034", "0 34 3333-4444"), às vezes com a operadora de 2 dígitos ("0 15 34 ..."):
  # nenhum DDD começa com 0 (varredura F14).
  LONGA_DISTANCIA = '0'.freeze
  DIGITOS_DA_OPERADORA = 2

  module_function

  # O DDD de "34", "(34) 3333-4444", "+55 34 99999-0000" ou "5534999990000": pelo tamanho do número (2 dígitos; 10 ou 11
  # com o DDD na frente; 12 ou 13 com o 55 do país antes). -> os 2 dígitos, ou nil (sem DDD, fora do plano, ou telefone
  # de outro país: com "+" e sem o "+55").
  def ddd_do_telefone(valor)
    texto = valor.to_s.strip
    return if de_outro_pais?(texto)

    ddd = ddd_dos_digitos(texto.delete("^#{Parametro::DIGITOS}"))
    ddd if Plano::ESTADOS.key?(ddd)
  end

  def de_outro_pais?(texto)
    texto.start_with?('+') && !texto.start_with?("+#{PAIS}")
  end

  def ddd_dos_digitos(digitos)
    return da_longa_distancia(digitos.delete_prefix(LONGA_DISTANCIA)) if digitos.start_with?(LONGA_DISTANCIA)

    case digitos.length
    when 2 then digitos
    when 10, 11 then digitos[0, 2]
    when 12, 13 then digitos[2, 2] if digitos.start_with?(PAIS)
    end
  end

  # Sem o 0: o DDD (2), o telefone (10 ou 11) ou a operadora na frente do telefone (12 ou 13).
  def da_longa_distancia(digitos)
    case digitos.length
    when 2, 10, 11 then digitos[0, 2]
    when 12, 13 then digitos[DIGITOS_DA_OPERADORA, 2]
    end
  end

  def resposta(ddd, sigla, cidades: nil)
    base = { 'ddd' => ddd }.merge(Autonomia::FerramentasProntas::Ufs.com_nome(sigla))
    return base.merge('observacao' => 'Só o estado: a lista de cidades não veio agora.') if cidades.nil?

    base.merge(Autonomia::FerramentasProntas::Lista.cortar(cidades, 'cidades', MAX_CIDADES))
  end

  DDD = Parametro.new(nome: 'ddd', descricao: 'O DDD (ex.: 31) ou o telefone inteiro do cliente: só o DDD sai daqui.',
                      deduza: 'tire o DDD do telefone do cliente (os 2 dígitos do código de área). Telefone com + e ' \
                              'código de outro país não é do Brasil: diga isso a ele, sem consultar.') do |valor|
    ddd_do_telefone(valor)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'ddd', slug: 'pronta_ddd', nome: 'DDD', flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'O estado e as cidades de um DDD (código de área do telefone).',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'ddd', descricao: 'o estado e as cidades do DDD', obrigatorios: [DDD], provedores: [BrasilApi, Plano],
        validade: 30.days, prazo_por_fonte: 3, prazo_total: 4
      )
    ],
    limite_diario: 500,
    termos: 'BrasilAPI (uso de pessoa real); o plano de numeração calculado aqui é a reserva. Cache de 30 dias.'
  )
end
