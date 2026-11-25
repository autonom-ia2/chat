# AS CONDIÇÕES GERAIS que o comparativo cita (#3211), tiradas da base do agente contratado, nunca escritas de memória:
# - `url`: o PDF oficial, lido da 1ª linha de `base/condicoes_gerais.md` (o comentário `<!-- fonte: ..., https://... -->`
#   que a base grava ao importar o documento). A base nova vale no deploy seguinte, sem tocar aqui;
# - `SEGURADORA`: o nome como a definição "Seguradora" das condições gerais escreve;
# - `PROCESSO_SUSEP`: o processo da mesma 1ª linha.
# O spec confere os três contra o arquivo.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CondicoesGerais
  SEGURADORA = 'Zurich Minas Brasil Seguros S.A'.freeze
  PROCESSO_SUSEP = '15414.644662/2023-04'.freeze

  module_function

  def arquivo
    Autonomia::Agents::Contratados::MODELOS.dig('seguro_viagem_universal', :pasta).join('base', 'condicoes_gerais.md')
  end

  # -> o endereço do PDF das condições gerais, ou nil se a 1ª linha não trouxer um.
  def url
    primeira_linha = File.open(arquivo, &:readline).strip.delete_suffix('-->')
    primeira_linha.split(', ').map(&:strip).find { |parte| parte.start_with?('https://') }
  end

  def seguradora
    "Seguradora: #{SEGURADORA}"
  end

  # Em palavras de leigo: o que é a SUSEP vai junto do número.
  def registro_susep
    "Registro na SUSEP (órgão do governo que fiscaliza seguros): #{PROCESSO_SUSEP}"
  end
end
