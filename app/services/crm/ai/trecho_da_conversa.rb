# #1920: o trecho de uma conversa real que vai como evidência à IA que escreve a frase. Só quem falou (o papel, nunca o
# nome) e o texto, curto, até o instante da decisão de uma pessoa. Os metadados vão sem id, nome, telefone ou data; o
# TEXTO vai como foi escrito, e só a instrução do modelo o impede de copiar dado pessoal para a frase
# (Crm::Ai::StageCriteriaImprover, Crm::Ai::WhenToUseImprover).
module Crm::Ai::TrechoDaConversa
  MAX_MENSAGENS = 8
  MAX_TEXTO = 300

  def self.de(card, ate:)
    Crm::Ai::ContextBuilder.new(card: card, ate: ate).mensagens.last(MAX_MENSAGENS).filter_map do |mensagem|
      texto = mensagem[:content].to_s.strip
      { role: mensagem[:role], content: texto.truncate(MAX_TEXTO) } if texto.present?
    end
  end
end
