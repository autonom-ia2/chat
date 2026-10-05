# Os fluxos da tela em que a pessoa está, para o Guia receber sempre.
#
# A busca do Guia usa o texto do pedido. Pedido longo e cheio de palavras de outro assunto
# ("lead", "contato", "empresa") trazia os fluxos da Prospecção e deixava de fora o da própria
# tela: na tela de criar automação, o Guia não recebia nem "Criar automação conversando" nem
# "Usar um Decisor na automação", e respondeu que precisava de integração (conta 16, 05/10/2026).
#
# A tela de cada fluxo vem do mapa gerado (`- rota:`) e as outras telas que ele atende, do campo
# `- cobre:` de porques.md. Conferência por igualdade de texto, nunca por padrão.
module Autonomia::Guide::FluxosDaTela
  MAX = 4
  ROTA = '- rota: `'.freeze
  COBRE = '- cobre:'.freeze

  module_function

  def para(agent, rota)
    nome = rota.to_s.strip
    return [] if agent.nil? || nome.empty?

    # O banco separa as candidatas pelo nome da tela no texto (sem o embedding, que é pesado); a
    # conferência exata fica no Ruby — "automacoes_nova" não pode casar com "automacoes_nova_x".
    trecho = "%#{::ActiveRecord::Base.sanitize_sql_like(nome)}%"
    ::Autonomia::Agents::KnowledgeEntry.where(autonomia_agent_id: agent.id, status: :ready)
                                       .where('content LIKE ?', trecho)
                                       .select(:id, :content, :source_id, :chunk_index)
                                       .order(:chunk_index)
                                       .select { |entrada| atende?(entrada.content, nome) }
                                       .first(MAX)
  end

  def atende?(conteudo, rota)
    conteudo.to_s.each_line.any? do |linha|
      linha.start_with?("#{ROTA}#{rota}`") || cobre(linha).include?(rota)
    end
  end

  def cobre(linha)
    return [] unless linha.start_with?(COBRE)

    linha.delete_prefix(COBRE).split(',').map(&:strip)
  end
end
