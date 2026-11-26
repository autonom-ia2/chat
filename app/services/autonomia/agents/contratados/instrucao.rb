# A INSTRUÇÃO DO AGENTE CONTRATADO, montada a cada turno: lê o arquivo do modelo (o deploy seguinte vale) e troca as
# quatro variáveis pelos dados da marca. Uma passada só e sem regex: o valor inserido nunca é relido, então um nome de
# corretora com `$nomeAgente` dentro não vira outro marcador.
module Autonomia::Agents::Contratados::Instrucao
  VARIAVEIS = {
    '$nomeAgente' => 'nome_agente',
    '$nomeCorretora' => 'nome_corretora',
    '$sobreCorretora' => 'sobre_corretora',
    '$dataDeHoje' => :hoje
  }.freeze
  MAX_NOME = 120
  MAX_SOBRE = 1_000
  DIAS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

  module_function

  # -> o texto pronto; nil para quem não é contratado ou tem modelo fora do catálogo.
  def renderizar(agent, hoje: nil)
    modelo = Autonomia::Agents::Contratados.modelo(agent)
    return if modelo.nil?

    marca = Autonomia::Agents::Contratados.marca(agent)
    %w[nome_agente nome_corretora].each do |campo|
      raise Autonomia::Agents::Contratados::DadosIncompletos, campo if marca[campo].to_s.strip.empty?
    end
    hoje ||= Autonomia::FerramentasProntas.fuso_da_conta(agent.account).today
    valores = marca.slice(*VARIAVEIS.values.grep(String)).merge(:hoje => data_por_extenso(hoje))
    substituir(modelo[:pasta].join(modelo[:arquivo]).read, valores)
  end

  def substituir(texto, valores)
    saida = +''
    pos = 0
    while (achado = texto.index('$', pos))
      saida << texto[pos...achado]
      marcador = VARIAVEIS.keys.find { |m| texto[achado, m.length] == m }
      if marcador
        saida << valores[VARIAVEIS[marcador]].to_s
        pos = achado + marcador.length
      else
        saida << '$'
        pos = achado + 1
      end
    end
    saida << texto[pos..].to_s
  end

  def data_por_extenso(data)
    "#{data.strftime('%d/%m/%Y')} (#{DIAS[data.wday]})"
  end

  def marcador_dentro?(valor)
    VARIAVEIS.keys.any? { |marcador| valor.to_s.include?(marcador) }
  end
end
