# #1426 (tema 4b) — o material do agente depois da leitura e da revisão: as conferências (vazio, leitura ruim,
# duplicado, tabela sem cabeçalho, contradição, páginas de fora) e o autoteste. Só na Fase 2 (piloto), nunca na Lia
# (instrução mantida pela Autonom.ia) nem num agente de sistema (o Guia). Fora disso, nada roda e a API devolve vazio.
module Autonomia::Agents::Material
  module_function

  def conferir?(agent)
    agent.present? && Autonomia::Agents::Fase2.ligada?(agent.account) && !agent.instrucao_mantida? &&
      agent.config.to_h['system_key'].blank?
  end

  # O nome do material como a pessoa o reconhece na lista.
  def nome(source)
    source.reference.presence || source.external_link.presence || source.source_type
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
