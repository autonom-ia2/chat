# Uma linha da memória em JSON, numa linha só, com a data absoluta no fuso da conta (nunca "Brasília") e a procedência
# legível. Ajuda para quem monta o bloco (Agentes IA); o teto do Leitor mede por aqui.
module Crm::Memoria::Leitor::Render
  ORIGENS = { cliente_informou: 'cliente informou', confirmado: 'confirmado', equipe: 'equipe informou',
              ferramenta: 'resultado de ferramenta', sistema: 'sistema' }.freeze

  module_function

  def json_linha(linha, fuso:)
    dados = { id: linha.id, campo: linha.rotulo, valor: linha.valor, origem: ORIGENS.fetch(linha.origem),
              em: linha.em&.in_time_zone(fuso)&.strftime('%d/%m/%Y %H:%M'), status: linha.status }
    dados[:card] = linha.card_id if linha.card_id
    dados.compact.to_json
  end
end
