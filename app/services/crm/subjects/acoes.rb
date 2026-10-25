# O que muda o assunto da conversa sem pessoa no meio, comum à IA de assunto (Applier, #1145) e ao agente que abre um
# assunto num funil (Abrir, #1447): voltar a um card aberto (foco) e criar o card do pedido novo na 1ª etapa do funil.
# Quem chama já está no lock da conversa (Crm::Conversations::SyncLock) e conferiu o que pode ter mudado.
module Crm::Subjects::Acoes
  module_function

  def focar(conversation:, card:)
    Crm::Cards::Focus.new(account: conversation.account, card: card, conversation: conversation).perform
  end

  # source: quem deu nome ao assunto ('ai' para a IA de assunto, 'agente' para o agente de IA). etapa: a coluna escolhida
  # pela IA de assunto (#1910); sem ela, a 1ª etapa. provisorio (#2163): o nome é genérico e pode ser refinado uma vez.
  def criar(conversation:, pipeline:, titulo:, source:, etapa: nil, provisorio: false) # rubocop:disable Metrics/ParameterLists
    subject = Crm::Subjects::NomeProvisorio.subject(source, titulo: titulo, provisorio: provisorio)
    Crm::Cards::Creator.new(
      account: conversation.account, user: nil, conversation: conversation,
      params: { pipeline_id: pipeline.id, stage_id: (etapa || Crm::Subjects::Etapa.primeira(pipeline)).id, title: titulo,
                metadata: { 'subject' => subject } }
    ).perform
  end
end
