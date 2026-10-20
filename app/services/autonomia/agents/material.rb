# #1426 (tema 4b) — o material do agente depois da leitura e da revisão: as conferências (vazio, leitura ruim,
# duplicado, tabela sem cabeçalho, contradição, páginas de fora) e o autoteste. Só na Fase 2 (piloto), nunca na Lia
# (instrução mantida pela Autonom.ia) nem num agente de sistema (o Guia). Fora disso, nada roda e a API devolve vazio.
module Autonomia::Agents::Material
  # Trecho menor que isto não vale a pena mandar ao modelo.
  MENOR_TRECHO = 40

  module_function

  def conferir?(agent)
    agent.present? && Autonomia::Agents::Fase2.ligada?(agent.account) && !agent.instrucao_mantida? &&
      agent.config.to_h['system_key'].blank?
  end

  # O nome do material como a pessoa o reconhece na lista.
  def nome(source)
    source.reference.presence || source.external_link.presence || source.source_type
  end

  # Reparte o orçamento de caracteres da entrada do modelo entre os materiais ANTES de serializar: cada um fica com a
  # mesma parte, e os trechos dele são cortados para caber nela. Nenhum material some do fim da lista e o JSON sai
  # sempre inteiro (nada é cortado depois de serializado). Cada material é um Hash com 'trechos' (lista de textos).
  def repartir(materiais, orcamento)
    return materiais if materiais.empty?

    parte = orcamento / materiais.size
    materiais.map do |material|
      fixo = material.merge('trechos' => []).to_json.size + 1 # + a vírgula entre os materiais
      material.merge('trechos' => caber(Array(material['trechos']), parte - fixo))
    end
  end

  # Os trechos, na ordem, até a sobra (medida no JSON de cada um, com as aspas e o escape). O que não cabe inteiro é
  # cortado; o resto fica de fora.
  def caber(trechos, sobra)
    trechos.each_with_object([]) do |trecho, cabem|
      espaco = sobra - cabem.sum { |texto| texto.to_json.size + 1 }
      break cabem if espaco < MENOR_TRECHO

      texto = trecho.to_s[0, espaco].to_s
      texto = texto[0, texto.size - 1] while texto.present? && texto.to_json.size + 1 > espaco
      cabem << texto if texto.present?
    end
  end

  # A "impressão digital" do que o agente usa: os materiais aprovados e o texto de cada um. Muda quando entra, sai ou é
  # relido um material aprovado. Medida objetiva (código), não interpreta texto.
  def hash_da_base(agent)
    partes = agent.sources.knowledge_sources.servable.order(:id).map do |source|
      "#{source.id}:#{source.metadata.to_h['hash_do_texto'] || source.reviewed_at&.to_i}"
    end
    Digest::SHA256.hexdigest(partes.join('|'))
  end
end
