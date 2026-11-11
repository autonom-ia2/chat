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

  module_function

  # O DDD de "34", "(34) 3333-4444", "+55 34 99999-0000" ou "5534999990000": pelo tamanho do número (2 dígitos; 10 ou 11
  # com o DDD na frente; 12 ou 13 com o 55 do país antes). -> os 2 dígitos, ou nil (sem DDD, ou fora do plano).
  def ddd_do_telefone(valor)
    digitos = valor.to_s.delete("^#{Parametro::DIGITOS}")
    ddd = case digitos.length
          when 2 then digitos
          when 10, 11 then digitos[0, 2]
          when 12, 13 then digitos[2, 2] if digitos.start_with?(PAIS)
          end
    ddd if Plano::ESTADOS.key?(ddd)
  end

  def resposta(ddd, sigla, cidades: nil)
    base = { 'ddd' => ddd }.merge(Autonomia::FerramentasProntas::Ufs.com_nome(sigla))
    return base.merge('observacao' => 'Só o estado: a lista de cidades não veio agora.') if cidades.nil?

    base.merge(Autonomia::FerramentasProntas::Lista.cortar(cidades, 'cidades', MAX_CIDADES))
  end

  DDD = Parametro.new(nome: 'ddd', descricao: 'O DDD (ex.: 31) ou o telefone inteiro do cliente: só o DDD sai daqui.',
                      deduza: 'tire o DDD do telefone do cliente (os 2 dígitos do código de área). Se o número não é do ' \
                              'Brasil, diga isso a ele.') do |valor|
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
