# #1920: o trecho de uma conversa real que vai como evidência à IA que escreve a frase. Só quem falou (o papel, nunca o
# nome) e o texto, curto, até o instante da decisão de uma pessoa. Sem id, nome, telefone ou data: o modelo é instruído a
# nunca copiar dado pessoal do texto para a frase (Crm::Ai::StageCriteriaImprover, Crm::Ai::WhenToUseImprover).
module Crm::Ai::TrechoDaConversa
  MAX_MENSAGENS = 8
  MAX_TEXTO = 300

  def self.de(card, ate:)
    Crm::Ai::ContextBuilder.new(card: card, ate: ate).perform[:recent_messages].last(MAX_MENSAGENS).filter_map do |mensagem|
      texto = mensagem[:content].to_s.strip
      { role: mensagem[:role], content: texto.truncate(MAX_TEXTO) } if texto.present?
    end
  end
end
