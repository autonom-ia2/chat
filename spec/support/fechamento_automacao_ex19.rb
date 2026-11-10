# As sondas da G42, da G43 e da G68, dos exemplos 1 e 19 (#2414 F9): rodam o código de verdade e conferem o efeito. Ficam
# fora do FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama as daqui.
module FechamentoAutomacao::SondasDoExemplo19
  module_function

  RESPOSTA = 'Meu número novo é (11) 98888-0019'.freeze

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

  # G68 (#2864, exemplo 19, passo 3): a execução mandou um e-mail, que abriu outra conversa do contato, e o cliente
  # respondeu lá. O "extrair" lê a resposta junto da conversa do alvo, pela mesma leitura que vai à IA. Roda na transação
  # do exemplo, que desfaz tudo.
  def extrair_le_a_resposta_do_email?
    conta = FactoryBot.create(:account)
    conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_ia')
    quem = FactoryBot.create(:user, account: conta, role: :administrator)
    FactoryBot.create(:custom_attribute_definition, account: conta, attribute_key: 'numero_novo', attribute_display_name: 'Número novo',
                                                    attribute_model: 'contact_attribute', attribute_display_type: 'text')
    conversa = FactoryBot.create(:conversation, account: conta)
    passo = { 'id' => 'numero_novo', 'tipo' => 'extrair', 'le' => %w[mensagens_recentes],
              'campos' => [{ 'chave' => 'numero_novo', 'descricao' => 'o número novo', 'destino' => 'contato.atributos.numero_novo' }] }
    execucao = execucao_com_email(conta, quem, conversa, passo)
    outras = o_que_o_extrair_le(execucao, passo, conversa)[:other_conversations]
    outras.to_json.include?(RESPOSTA)
  end

  # G42 (#2721, exemplo 1, passo 12; exemplo 19, passo 7): a execução tentou o modelo no WhatsApp e o e-mail, e os dois
  # falharam. O "resumir" recebe os envios dos dois canais, cada um marcado como não entregue, pela mesma leitura que vai
  # à IA. Roda na transação do exemplo, que desfaz tudo.
  def resumir_le_os_envios_dos_dois_canais?
    conta = FactoryBot.create(:account)
    conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_ia')
    quem = FactoryBot.create(:user, account: conta, role: :administrator)
    whatsapp = FactoryBot.create(:channel_whatsapp, account: conta, sync_templates: false, validate_provider_config: false)
    conversa = FactoryBot.create(:conversation, account: conta, inbox: whatsapp.inbox)
    passo = { 'id' => 'resumo', 'tipo' => 'resumir', 'le' => %w[mensagens_recentes], 'destino' => 'nota' }
    execucao = execucao_com_falhas(conta, quem, conversa, passo)
    envios = o_que_o_resumir_le(execucao, passo, conversa)[:automation_sends].to_a
    envios.map { |envio| [envio[:channel], envio[:not_delivered]] }.sort == [['email', true], ['whatsapp', true]]
  end

  # A execução com o modelo (na conversa do alvo) e o e-mail (em conversa própria), os dois falhos, nos registros ok com
  # `mensagem_id`, como os passos "mensagem" e "email" gravam.
  def execucao_com_falhas(conta, quem, conversa, passo)
    definicao = FactoryBot.create(:autonomia_automacao, account: conta, ligada_por: quem)
    versao = definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }, autor: nil)
    execucao = FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: conversa, chave_gatilho: 'conversa.resolvida')
    do_email = FactoryBot.create(:conversation, account: conta, contact: conversa.contact,
                                                inbox: FactoryBot.create(:channel_email, account: conta).inbox)
    [[conversa, 'modelo'], [do_email, 'email']].each do |onde, passo_id|
      enviado = FactoryBot.create(:message, conversation: onde, account: conta, inbox: onde.inbox, message_type: :outgoing,
                                            content: "Sonda G42, #{passo_id}", status: :failed)
      Autonomia::Automacao::Registro.create!(account: conta, automacao: definicao, execucao: execucao, passo: passo_id, resultado: 'ok',
                                             dados: { 'mensagem_id' => enviado.id })
    end
    execucao
  end

  # A leitura do passo, a mesma que vai à IA na execução (PassoDeResumir#leitura_da_execucao, privada).
  def o_que_o_resumir_le(execucao, passo, conversa)
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao, chave_gatilho: execucao.chave_gatilho)
    resumir = Autonomia::Automacao::PassoDeResumir.new(execucao: execucao, passo: passo, alvo: conversa, acesso: acesso)
    resumir.send(:leitura_da_execucao).conversa
  end

  # A execução do passo, com o e-mail que ela mandou (registro ok com `mensagem_id`) e a resposta do cliente.
  def execucao_com_email(conta, quem, conversa, passo)
    definicao = FactoryBot.create(:autonomia_automacao, account: conta, ligada_por: quem)
    versao = definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }, autor: nil)
    execucao = FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: conversa, chave_gatilho: 'conversa.resolvida')
    do_email = FactoryBot.create(:conversation, account: conta, contact: conversa.contact)
    enviado = FactoryBot.create(:message, conversation: do_email, account: conta, inbox: do_email.inbox, message_type: :outgoing,
                                          content: 'Você trocou de WhatsApp?')
    FactoryBot.create(:message, conversation: do_email, account: conta, inbox: do_email.inbox, sender: conversa.contact,
                                message_type: :incoming, content: RESPOSTA)
    Autonomia::Automacao::Registro.create!(account: conta, automacao: definicao, execucao: execucao, passo: 'email', resultado: 'ok',
                                           dados: { 'mensagem_id' => enviado.id })
    execucao
  end

  # A leitura do passo, a mesma que vai à IA na execução (PassoDeExtrair#leitura_da_execucao, privada).
  def o_que_o_extrair_le(execucao, passo, conversa)
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao, chave_gatilho: execucao.chave_gatilho)
    extrair = Autonomia::Automacao::PassoDeExtrair.new(execucao: execucao, passo: passo, alvo: conversa, acesso: acesso)
    extrair.send(:leitura_da_execucao, nil).conversa
  end
end
