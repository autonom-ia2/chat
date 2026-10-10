# Multifunil 5/11 (#1145): a IA identifica de que assunto o cliente está falando.
#
# A cada mensagem recebida (com espera para juntar rajadas), o Jev escolhe entre: ainda não dá para saber, continua
# no assunto atual, voltou a um assunto aberto, ou é um pedido novo num funil da caixa. O modelo maior entra só na
# dúvida e quando é preciso dar nome ao assunto (o Jev só escolhe, não escreve). Na dúvida, nada muda.
# Nunca regex nem lista de palavras para interpretar o cliente (R17).
module Crm::Subjects
  # Espera depois da última mensagem, como a avaliação de etapa: uma rajada vira uma pergunta só.
  DEBOUNCE = 15.seconds
  # Abaixo disso o Jev está em dúvida e o modelo maior decide.
  CERTEZA_MINIMA = 0.8
  # Teto de perguntas ao Jev por conta e mês (o custo do Jev é nosso).
  LIMITE_MENSAL = 10_000
  # Assuntos abertos que o Jev vê como opção; os mais recentes primeiro.
  MAX_ASSUNTOS = 8
  FEATURE = 'assunto'.freeze
  FEATURE_REVISAO = 'assunto_revisao'.freeze

  # A caixa da conversa tem o CRM e a IA de assunto ligados.
  def self.ligado?(conversation)
    Crm::InboxSetting.where(account_id: conversation.account_id, inbox_id: conversation.inbox_id, crm_enabled: true)
                     .where.not(subject_ai_mode: :off).exists?
  end
end
