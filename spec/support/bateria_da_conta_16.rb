# A conta 16 (#860) da bateria do Guia (bateria_do_guia.rb): leads de um formulário do site chegando por
# e-mail na caixa Comercial. Fica num arquivo próprio para a conta da corretora continuar legível.
module BateriaDaConta16
  # Conta 16 (#860): a caixa Comercial, o funil dela, os quatro leads do formulário e os dois e-mails comuns.
  Formularios = Struct.new(:comercial, :funil, :novo, :leads, :comuns, keyword_init: true)
  Lead = Struct.new(:nome, :telefone, :telefone_escrito, :empresa, :produto, :email, :aceite, :corpo, :contato, :conversa, :card,
                    keyword_init: true)

  ACEITE_DO_FORMULARIO = '[x] Aceito receber contato da Corretora X e concordo com a Política de Privacidade (LGPD).'.freeze
  # Três dos quatro marcaram o aceite (C24). O telefone vem escrito como a pessoa digitou; o E.164 é o que se espera gravado.
  LEADS_DO_FORMULARIO = [
    { nome: 'Juliana Prado', telefone: '+5511987654321', telefone_escrito: '(11) 98765-4321', empresa: 'Transportes Prado Ltda',
      produto: 'Seguro de frota', email: 'juliana@transportesprado.com.br', aceite: true },
    { nome: 'Rafael Nogueira', telefone: '+5521998765432', telefone_escrito: '(21) 99876-5432', empresa: 'Clínica Nogueira',
      produto: 'Seguro empresarial', email: 'rafael@clinicanogueira.com.br', aceite: true },
    { nome: 'Marcos Teixeira', telefone: '+5531976543210', telefone_escrito: '31 97654-3210', empresa: 'Padaria Pão Dourado',
      produto: 'Plano de saúde empresarial', email: 'marcos@paodourado.com.br', aceite: true },
    { nome: 'Beatriz Lima', telefone: '+5541965432109', telefone_escrito: '(41) 96543-2109', empresa: 'Lima Arquitetura',
      produto: 'Seguro de vida em grupo', email: 'beatriz@limaarquitetura.com.br', aceite: false }
  ].freeze
  EMAILS_COMUNS = [
    { nome: 'Anthropic', email: 'news@mail.anthropic.com',
      corpo: 'Anthropic News — o que lançamos este mês. Leia as novidades no nosso blog. Para sair da lista, clique aqui.' },
    { nome: 'Gráfica Rápida', email: 'financeiro@graficarapida.com.br',
      corpo: 'Olá! Segue o boleto da impressão dos folhetos, com vencimento no dia 15. Qualquer dúvida, estamos à disposição.' }
  ].freeze

  # A conta 16 (#860), montada sobre a corretora: leads de um formulário do site chegam por e-mail na caixa
  # Comercial, com o card automático ligado e o rodízio desligado. Como em produção, o contato nasce com o
  # e-mail no lugar do nome, sem telefone, numa empresa batizada pelo domínio, e todo e-mail vira card em
  # Novo sem responsável — inclusive a newsletter e o fornecedor, que não são lead.
  def conta_formularios!(base)
    base.conta.enable_features!('companies')
    pecas = { conta: base.conta, comercial: caixa_comercial!(base.conta, [base.ana, base.bruno]) }
    pecas = pecas.merge(funil_comercial!(pecas, base.admin))
    Formularios.new(comercial: pecas[:comercial], funil: pecas[:funil], novo: pecas[:novo],
                    leads: LEADS_DO_FORMULARIO.map { |dados| lead_do_formulario!(pecas, dados) },
                    comuns: EMAILS_COMUNS.map { |dados| email_comum!(pecas, dados) })
  end

  def caixa_comercial!(conta, membros)
    canal = Channel::Email.create!(account: conta, email: 'comercial@corretora-x.com.br',
                                   forward_to_email: "comercial-#{SecureRandom.hex(4)}@entrada.invalid")
    caixa = conta.inboxes.create!(name: 'Comercial', channel: canal, enable_auto_assignment: false)
    caixa.add_members(membros.map(&:id))
    caixa
  end

  def funil_comercial!(pecas, admin)
    conta = pecas[:conta]
    funil, novo = create_crm_pipeline(account: conta, user: admin, name: 'Comercial')
    novo.update!(name: 'Novo')
    conta.crm_inbox_settings.create!(inbox: pecas[:comercial], crm_enabled: true, auto_create_card: true, default_pipeline_id: funil.id)
    conta.crm_pipeline_inboxes.create!(pipeline: funil, inbox: pecas[:comercial], default_stage: novo, auto_create_card: true,
                                       created_by: admin)
    { funil: funil, novo: novo }
  end

  # A empresa leva o nome tirado do domínio (Contacts::CompanyAssociationService), não o do formulário.
  def lead_do_formulario!(pecas, dados)
    dominio = dados[:email].split('@').last
    empresa = Company.create!(account: pecas[:conta], name: dominio.split('.').first.titleize, domain: dominio)
    contato = pecas[:conta].contacts.create!(name: dados[:email], email: dados[:email], company_id: empresa.id)
    conversa, card = email_recebido!(pecas, contato, corpo_do_formulario(dados))
    Lead.new(**dados, contato: contato, conversa: conversa, card: card)
  end

  def email_comum!(pecas, dados)
    contato = pecas[:conta].contacts.create!(name: dados[:nome], email: dados[:email])
    conversa, card = email_recebido!(pecas, contato, dados[:corpo])
    Lead.new(**dados, contato: contato, conversa: conversa, card: card)
  end

  # O caminho de produção: a mensagem chega e o CardSyncer cria o card na etapa padrão da caixa.
  def email_recebido!(pecas, contato, corpo)
    conversa = create_crm_conversation(account: pecas[:conta], inbox: pecas[:comercial], contact: contato)
    mensagem = create_incoming_message(conversation: conversa, content: corpo)
    [conversa, Crm::Conversations::CardSyncer.new(conversation: conversa, message: mensagem).perform]
  end

  def corpo_do_formulario(dados)
    ['Novo envio do formulário do site corretora-x.com.br', '', "Nome: #{dados[:nome]}", "E-mail: #{dados[:email]}",
     "Telefone: #{dados[:telefone_escrito]}", "Empresa: #{dados[:empresa]}", "Produto: #{dados[:produto]}",
     ('' if dados[:aceite]), (ACEITE_DO_FORMULARIO if dados[:aceite])].compact.join("\n")
  end
end

RSpec.configure do |config|
  config.include BateriaDaConta16, :bateria_guia
end
