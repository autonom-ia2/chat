# A sonda da G43, do exemplo 19 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo19
  module_function

  # G43: o número da conversa morreu (a última mensagem da empresa nela falhou) e o telefone do contato é outro; o passo
  # "mensagem" manda na conversa do número novo, na mesma caixa. No SMS, que não tem janela. Roda na transação do
  # exemplo, que desfaz tudo; o envio ao canal só fica na fila.
  def mensagem_vai_ao_numero_novo?
    account = FactoryBot.create(:account)
    caixa = FactoryBot.create(:channel_sms, account: account).inbox
    contato = FactoryBot.create(:contact, account: account, phone_number: '+5511900000043')
    conversa = conversa_com_o_numero_morto(caixa, contato)
    contato.update!(phone_number: '+5511988880043')
    automacao = FactoryBot.create(:autonomia_automacao, account: account,
                                                        ligada_por: FactoryBot.create(:user, account: account, role: :administrator))
    execucao = FactoryBot.create(:autonomia_automacao_execucao, automacao: automacao, alvo: conversa,
                                                                versao: FactoryBot.create(:autonomia_automacao_versao, automacao: automacao))
    passo = { 'id' => 'sonda', 'tipo' => 'mensagem', 'texto' => ['Sonda G43'] }
    Autonomia::Automacao::PassoDeMensagem.new(execucao: execucao, passo: passo, alvo: conversa).executar
    novo = ContactInbox.find_by(inbox: caixa, contact: contato, source_id: '+5511988880043')
    novo.present? && Message.exists?(conversation: novo.conversations, message_type: :outgoing, content: 'Sonda G43')
  end

  def conversa_com_o_numero_morto(caixa, contato)
    antigo = FactoryBot.create(:contact_inbox, inbox: caixa, contact: contato, source_id: contato.phone_number)
    conversa = FactoryBot.create(:conversation, account: caixa.account, inbox: caixa, contact: contato, contact_inbox: antigo)
    FactoryBot.create(:message, conversation: conversa, account: caixa.account, inbox: caixa, message_type: :outgoing,
                                content: 'Sonda G43, antes', status: :failed)
    conversa
  end
end
