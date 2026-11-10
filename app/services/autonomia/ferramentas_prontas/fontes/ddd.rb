# DDD (#2858, F1): o estado e as cidades de um código de área.
#   - principal: BrasilAPI (estado e cidades, da Anatel);
#   - reserva: o plano de numeração calculado aqui (`ddd/plano.rb`), sem rede: o estado de cada DDD, que é fixo. Sem
#     as cidades, e a resposta diz isso.
# Só o DDD vai à fonte, nunca o telefone. Termos: BrasilAPI pede uso com "natureza de uma pessoa real". Cache de 30 dias.
module Autonomia::FerramentasProntas::Fontes::Ddd
  Parametro = Autonomia::FerramentasProntas::Parametro

  MAX_CIDADES = 200

  module_function

  def resposta(ddd, sigla, cidades: nil)
    base = { 'ddd' => ddd }.merge(Autonomia::FerramentasProntas::Ufs.com_nome(sigla))
    return base.merge('observacao' => 'Só o estado: a lista de cidades não veio agora.') if cidades.nil?

    base.merge(Autonomia::FerramentasProntas::Lista.cortar(cidades, 'cidades', MAX_CIDADES))
  end

  DDD = Parametro.new(nome: 'ddd', descricao: 'Os 2 dígitos do código de área (ex.: 31). Só o DDD, nunca o telefone.') do |valor|
    digitos = Parametro.digitos(valor, 2)
    digitos if digitos && Plano::ESTADOS.key?(digitos)
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
    limite_diario: 300,
    termos: 'BrasilAPI (uso de pessoa real); o plano de numeração calculado aqui é a reserva. Cache de 30 dias.'
  )
end
