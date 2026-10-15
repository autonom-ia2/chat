require 'rails_helper'

# Acha ou cria o modelo aprovado de uma finalidade (#1518). A Meta é sempre o `MetaClient` falso: nada sai daqui.
RSpec.describe Whatsapp::Templates::Garantir do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Whatsapp::Templates::MetaClient) }
  let(:pronto) { Whatsapp::Templates::Finalidades.pronto(:cobranca_vencimento, momento: :antes, com_valor: true) }
  let(:outcome) { Whatsapp::Templates::MetaClient::Outcome }

  before { allow(Whatsapp::Templates::MetaClient).to receive(:new).with(inbox: inbox).and_return(client) }

  def garantir(**opcoes)
    described_class.call(inbox: inbox, finalidade: :cobranca_vencimento, momento: :antes, com_valor: true, **opcoes)
  end

  def listed(status, extra = {})
    pronto.corpo.deep_stringify_keys.merge('id' => '901', 'status' => status).merge(extra)
  end

  def put_in_list(*templates)
    channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
  end

  # Autorização do dono (#1586): uma linha do registro, como a tela grava.
  def autorizar(acao = WhatsappTemplateConsent::LIGOU, conta: account)
    WhatsappTemplateConsent.create!(account: conta, marca: 'utility', acao: acao, versao_aviso: 'v1', texto_aviso: 'Aviso.')
  end

  # Sem a autorização, criar para antes de falar com a Meta: nem o cliente é montado, nada é gravado.
  describe 'autorização do dono para criar (#1586)' do
    it 'sem autorização: sem_consentimento, sem falar com a Meta nem gravar lista ou perfil' do
      expect(garantir).to eq(status: :indisponivel, motivo: 'sem_consentimento')

      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
      expect(channel.reload.message_templates).to eq([])
      expect(WhatsappTemplateProfile.count).to eq(0)
    end

    it 'ligada e depois desligada: vale a última linha' do
      autorizar
      autorizar(WhatsappTemplateConsent::DESLIGOU)

      expect(garantir).to eq(status: :indisponivel, motivo: 'sem_consentimento')
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
    end

    it 'a autorização de outra conta não vale' do
      autorizar(conta: create(:account))

      expect(garantir).to eq(status: :indisponivel, motivo: 'sem_consentimento')
    end

    it 'ligada: cria pela Meta' do
      autorizar
      allow(client).to receive(:create).and_return(outcome.new(template: listed('PENDING'), created: true))

      expect(garantir).to eq(status: :em_analise, nome: pronto.nome, idioma: 'pt_BR')
      expect(client).to have_received(:create)
    end

    it 'sem autorização, o modelo que já está na lista continua valendo' do
      put_in_list(listed('APPROVED'))

      expect(garantir).to include(status: :pronto, nome: pronto.nome)
    end

    it 'criar: false não muda: fora da lista é ausente' do
      expect(garantir(criar: false)).to eq(status: :indisponivel, motivo: 'ausente')
    end
  end

  describe 'quando o modelo já está na lista da caixa' do
    it 'aprovado: devolve pronto com nome, idioma, categoria e campos, sem falar com a Meta' do
      put_in_list(listed('APPROVED'))
      allow(client).to receive(:create)

      expect(garantir).to eq(status: :pronto, nome: pronto.nome, idioma: 'pt_BR', categoria: 'UTILITY', campos: pronto.campos)
      expect(client).not_to have_received(:create)
    end

    it 'grava o perfil do sistema que faltava (modelo que entrou na lista por outro caminho)' do
      put_in_list(listed('APPROVED'))

      garantir

      expect(WhatsappTemplateProfile.find_by!(inbox: inbox, name: pronto.nome))
        .to have_attributes(system_owner: 'cobranca', fields: pronto.campos, meta_template_id: '901', created_by: nil)
    end

    it 'lê a lista do banco, não a do objeto da caixa carregado antes' do
      inbox.channel.message_templates # carrega o objeto com a lista vazia
      Channel::Whatsapp.where(id: channel.id).update_all(message_templates: [listed('APPROVED')]) # rubocop:disable Rails/SkipsModelValidations

      expect(inbox.channel.message_templates).to eq([])
      expect(garantir).to include(status: :pronto)
    end

    it 'perfil que não pode ser gravado (outra WABA com o mesmo nome) não esconde a situação do modelo' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: 'waba_antiga', name: pronto.nome, language: 'pt_BR')
      put_in_list(listed('PENDING'))

      expect(garantir).to eq(status: :em_analise, nome: pronto.nome, idioma: 'pt_BR')
    end

    it 'aprovado com o nome do pronto e outro texto (feito à mão na Meta): indisponível' do
      put_in_list(listed('APPROVED', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi, {{1}}! Outra coisa {{2}} aqui.' }]))

      expect(garantir).to eq(status: :indisponivel, motivo: 'texto_diferente')
    end

    # Outro job grava o perfil entre a leitura e a gravação deste: a colisão real do índice único é relida uma vez.
    it 'dois jobs ao mesmo tempo: o segundo acha o perfil do primeiro, sem estourar nem duplicar' do
      put_in_list(listed('APPROVED'))
      outro_job_gravou = false
      allow(WhatsappTemplateProfile).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap do
          next if outro_job_gravou

          outro_job_gravou = true
          original.call(account_id: account.id, inbox: inbox, waba_id: channel.waba_id, name: pronto.nome, language: 'pt_BR').save!
        end
      end

      expect(garantir).to include(status: :pronto)
      expect(WhatsappTemplateProfile.where(name: pronto.nome).sole).to have_attributes(system_owner: 'cobranca', meta_template_id: '901')
    end

    it 'aprovado com a categoria trocada pela Meta: devolve a categoria que a Meta deu' do
      put_in_list(listed('APPROVED', 'category' => 'MARKETING'))

      expect(garantir).to include(status: :pronto, categoria: 'MARKETING')
    end

    it 'acha o idioma sem diferenciar maiúscula' do
      put_in_list(listed('APPROVED', 'language' => 'PT_BR'))

      expect(garantir(idioma: 'pt_br')).to include(status: :pronto, idioma: 'PT_BR')
    end

    it 'em análise: não cria de novo' do
      put_in_list(listed('PENDING'))
      allow(client).to receive(:create)

      expect(garantir).to eq(status: :em_analise, nome: pronto.nome, idioma: 'pt_BR')
      expect(client).not_to have_received(:create)
    end

    it 'recusado: indisponível com o motivo da Meta, sem criar de novo' do
      put_in_list(listed('REJECTED', 'rejected_reason' => 'INVALID_FORMAT'))
      allow(client).to receive(:create)

      expect(garantir).to eq(status: :indisponivel, motivo: 'recusado', detalhe: 'INVALID_FORMAT', nome: pronto.nome, idioma: 'pt_BR')
      expect(client).not_to have_received(:create)
    end

    it 'pausado ou desativado: indisponível' do
      put_in_list(listed('PAUSED'))
      expect(garantir).to include(status: :indisponivel, motivo: 'pausado')

      put_in_list(listed('DISABLED'))
      expect(garantir).to include(status: :indisponivel, motivo: 'desativado')
    end

    it 'aprovado num formato que o envio não manda: indisponível' do
      put_in_list(listed('APPROVED', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}.' },
                                                      { 'type' => 'HEADER', 'format' => 'LOCATION' }]))

      expect(garantir).to include(status: :indisponivel, motivo: 'formato')
    end

    it 'modelo de outra finalidade ou da pessoa não serve' do
      autorizar
      put_in_list(listed('APPROVED', 'name' => 'boas_vindas'))
      allow(client).to receive(:create).and_return(outcome.new(template: listed('PENDING'), created: true))

      expect(garantir).to include(status: :em_analise)
      expect(client).to have_received(:create).once
    end
  end

  describe 'quando o modelo não está na lista da caixa' do
    before { autorizar }

    it 'cria o pronto pela Meta, põe na lista e grava o perfil do sistema (sem quem criou)' do
      allow(client).to receive(:create).and_return(outcome.new(template: listed('PENDING'), created: true))

      expect(garantir).to eq(status: :em_analise, nome: pronto.nome, idioma: 'pt_BR')

      expect(client).to have_received(:create).with(pronto.corpo.deep_stringify_keys)
      expect(channel.reload.message_templates.map { |item| item['name'] }).to eq([pronto.nome])
      profile = WhatsappTemplateProfile.find_by!(inbox: inbox, name: pronto.nome, language: 'pt_BR')
      expect(profile).to have_attributes(system_owner: 'cobranca', created_by: nil, fields: pronto.campos, meta_template_id: '901',
                                         friendly_name: pronto.nome_amigavel, waba_id: channel.waba_id, account_id: account.id)
    end

    it 'já existia aprovado na Meta (fora da lista): devolve pronto e põe na lista' do
      allow(client).to receive(:create).and_return(outcome.new(template: listed('APPROVED'), created: false))

      expect(garantir).to include(status: :pronto, nome: pronto.nome)
      expect(channel.reload.message_templates.first['status']).to eq('APPROVED')
    end

    it 'já existia recusado na Meta: indisponível' do
      allow(client).to receive(:create).and_return(outcome.new(template: listed('REJECTED'), created: false))

      expect(garantir).to include(status: :indisponivel, motivo: 'recusado')
    end

    it 'perfil que já existe para o nome é reaproveitado' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: pronto.nome, language: 'pt_BR')
      allow(client).to receive(:create).and_return(outcome.new(template: listed('PENDING'), created: true))

      garantir

      expect(WhatsappTemplateProfile.where(name: pronto.nome).count).to eq(1)
      expect(WhatsappTemplateProfile.find_by(name: pronto.nome).system_owner).to eq('cobranca')
    end

    it 'perfil que não pode ser gravado: indisponível, sem criar na Meta' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: 'waba_antiga', name: pronto.nome, language: 'pt_BR')
      allow(client).to receive(:create)

      expect(garantir).to eq(status: :indisponivel, motivo: 'perfil_invalido')
      expect(client).not_to have_received(:create)
    end

    it 'Meta fora do ar: indisponível, sem nada gravado' do
      allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::Unreachable, 'Net::ReadTimeout')

      expect(garantir).to eq(status: :indisponivel, motivo: 'meta_fora')
      expect(channel.reload.message_templates).to eq([])
      expect(WhatsappTemplateProfile.count).to eq(0)
    end

    it 'sem permissão na WABA: indisponível com o código' do
      error = Whatsapp::Templates::MetaClient::MetaError.new('sem permissão', own_text: true, code: 'permission_denied')
      allow(client).to receive(:create).and_raise(error)

      expect(garantir).to eq(status: :indisponivel, motivo: 'sem_permissao')
    end

    it 'a Meta recusou o pedido: indisponível, sem o texto dela' do
      allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::MetaError, 'texto da Meta')

      expect(garantir).to eq(status: :indisponivel, motivo: 'meta_recusou')
    end

    # Os prontos reais passam na conferência (finalidades_spec): o stub só prova que o caminho existe.
    it 'pronto que não passa na conferência estrutural não chega à Meta' do
      allow(Whatsapp::Templates::SubmitFormat).to receive(:problems).and_return(['media_required'])
      allow(client).to receive(:create)

      expect(garantir).to eq(status: :indisponivel, motivo: 'formato')
      expect(client).not_to have_received(:create)
    end
  end

  it 'caixa sem WhatsApp oficial: indisponível, sem falar com a Meta' do
    api_inbox = create(:inbox, account: account)

    result = described_class.call(inbox: api_inbox, finalidade: :cobranca_vencimento, momento: :antes, com_valor: false)

    expect(result).to eq(status: :indisponivel, motivo: 'sem_whatsapp_oficial')
  end

  it 'idioma sem pronto: indisponível' do
    expect(garantir(idioma: 'en')).to eq(status: :indisponivel, motivo: 'idioma_sem_pronto')
  end

  it 'finalidade desconhecida é erro de quem chama' do
    expect { described_class.call(inbox: inbox, finalidade: :boas_vindas) }
      .to raise_error(Whatsapp::Templates::Finalidades::Desconhecida)
  end

  it 'pronto com botões: devolve a posição de cada botão em `botoes`, e `campos` só com o corpo (#1524)' do
    finalidade = { 'teste_botoes' => { dono: 'agendamento', opcoes: [], variantes: { [] => {
      nome: 'teste_botoes_v1', amigavel: 'Teste', campos: %w[cliente.primeiro_nome negocio.prazo],
      texto: 'Olá, {{1}}! Seu horário é {{2}}. Use os botões abaixo.',
      botoes: [{ tipo: 'quick_reply', texto: 'Parar avisos', payload: 'stop_notices' },
               { tipo: 'url', texto: 'Ver meu horário', url: 'https://chat.hub2you.ai/b/{{1}}', campo: 'horario.link_codigo', exemplo: 'AB3' }]
    } } } }
    stub_const('Whatsapp::Templates::Finalidades::CATALOGO', Whatsapp::Templates::Finalidades::CATALOGO.merge(finalidade))
    teste = Whatsapp::Templates::Finalidades.pronto(:teste_botoes)
    put_in_list(teste.corpo.deep_stringify_keys.merge('id' => '902', 'status' => 'APPROVED'))

    expect(described_class.call(inbox: inbox, finalidade: :teste_botoes)).to eq(
      status: :pronto, nome: 'teste_botoes_v1', idioma: 'pt_BR', categoria: 'UTILITY',
      campos: { '1' => 'cliente.primeiro_nome', '2' => 'negocio.prazo' },
      botoes: [{ 'indice' => 0, 'tipo' => 'quick_reply', 'payload' => 'stop_notices' },
               { 'indice' => 1, 'tipo' => 'url', 'campo' => 'horario.link_codigo' }]
    )
  end

  # O `Route` do agendamento pergunta numa requisição web (#1524): lá só se lê. Nada de Meta, banco ou fila.
  describe 'só leitura (criar: false)' do
    # Todo SQL que não é leitura, enquanto o bloco roda.
    def escritas(&)
      sqls = []
      anotar = ->(*, payload) { sqls << payload[:sql] unless payload[:name] == 'SCHEMA' }
      ActiveSupport::Notifications.subscribed(anotar, 'sql.active_record', &)
      sqls.reject { |sql| sql.lstrip.upcase.start_with?('SELECT') }
    end

    def so_ler
      resultado = nil
      sqls = nil
      expect { sqls = escritas { resultado = garantir(criar: false) } }.not_to have_enqueued_job
      expect(sqls).to eq([])
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
      resultado
    end

    before { allow(Whatsapp::Templates::MetaClient).to receive(:new) }

    it 'fora da lista: indisponível com o motivo ausente, sem criar nem gravar' do
      expect(so_ler).to eq(status: :indisponivel, motivo: 'ausente')
      expect(channel.reload.message_templates).to eq([])
      expect(WhatsappTemplateProfile.count).to eq(0)
    end

    it 'aprovado: pronto, sem gravar o perfil que faltava' do
      put_in_list(listed('APPROVED'))

      expect(so_ler).to eq(status: :pronto, nome: pronto.nome, idioma: 'pt_BR', categoria: 'UTILITY', campos: pronto.campos)
      expect(WhatsappTemplateProfile.count).to eq(0)
    end

    it 'em análise, recusado e texto diferente: os mesmos motivos de sempre' do
      put_in_list(listed('PENDING'))
      expect(so_ler).to eq(status: :em_analise, nome: pronto.nome, idioma: 'pt_BR')

      put_in_list(listed('REJECTED', 'rejected_reason' => 'INVALID_FORMAT'))
      expect(so_ler).to include(status: :indisponivel, motivo: 'recusado', detalhe: 'INVALID_FORMAT')

      put_in_list(listed('APPROVED', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi, {{1}}! Outra coisa {{2}} aqui.' }]))
      expect(so_ler).to eq(status: :indisponivel, motivo: 'texto_diferente')
    end

    it 'perfil existente não é tocado' do
      put_in_list(listed('APPROVED'))
      perfil = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: pronto.nome,
                                               language: 'pt_BR')

      so_ler

      expect(perfil.reload).to have_attributes(system_owner: nil, meta_template_id: nil)
    end
  end

  # Aprovado só serve com os botões do pronto: tipo, texto, URL e ordem (#1524).
  describe 'botões' do
    let(:catalogo_teste) do
      { 'teste_link' => { dono: 'agendamento', opcoes: [], variantes: { [] => {
        nome: 'teste_link_v1', amigavel: 'Teste', campos: %w[cliente.primeiro_nome horario.data_hora],
        texto: 'Olá, {{1}}! Seu horário é {{2}}. Use os botões abaixo.',
        botoes: [{ tipo: 'url', texto: 'Ver meu horário', url: { base: :booking_invite, caminho: '/b/{{1}}' }, campo: 'horario.link_codigo' },
                 { tipo: 'quick_reply', texto: 'Parar avisos', payload: 'stop_notices' }]
      } } } }
    end
    let(:hub2you) { 'https://chat.hub2you.ai' }

    before { stub_const('Whatsapp::Templates::Finalidades::CATALOGO', Whatsapp::Templates::Finalidades::CATALOGO.merge(catalogo_teste)) }

    def aprovado_com(buttons)
      teste = with_modified_env(FRONTEND_URL: hub2you) { Whatsapp::Templates::Finalidades.pronto(:teste_link).corpo.deep_stringify_keys }
      components = teste['components'].reject { |component| component['type'] == 'BUTTONS' }
      components << { 'type' => 'BUTTONS', 'buttons' => buttons } if buttons
      put_in_list(teste.merge('id' => '903', 'status' => 'APPROVED', 'components' => components))
    end

    def url(endereco = "#{hub2you}/b/{{1}}")
      { 'type' => 'URL', 'text' => 'Ver meu horário', 'url' => endereco, 'example' => ["#{hub2you}/b/AB3K9QXZ"] }
    end

    def parar(texto = 'Parar avisos')
      { 'type' => 'QUICK_REPLY', 'text' => texto }
    end

    def garantir_link
      with_modified_env(FRONTEND_URL: hub2you) { described_class.call(inbox: inbox, finalidade: :teste_link, criar: false) }
    end

    it 'os mesmos botões, com a URL escrita de outro jeito (maiúscula no domínio): pronto' do
      aprovado_com([url('HTTPS://Chat.Hub2You.AI/b/{{1}}'), parar])

      expect(garantir_link).to include(status: :pronto, botoes: [{ 'indice' => 0, 'tipo' => 'url', 'campo' => 'horario.link_codigo' },
                                                                 { 'indice' => 1, 'tipo' => 'quick_reply', 'payload' => 'stop_notices' }])
    end

    it 'outro texto de botão, outra URL, outra ordem, botão a menos ou sem botões: indisponível' do
      [[url, parar('Sair')], [url('https://outro.site/b/{{1}}'), parar], [url("#{hub2you}/x/{{1}}"), parar],
       [url("#{hub2you}/b/fixo"), parar], [url("#{hub2you}/b/variavel"), parar], [parar, url], [url], nil].each do |buttons|
        aprovado_com(buttons)
        expect(garantir_link).to eq(status: :indisponivel, motivo: 'botoes_diferentes'), buttons.inspect
      end
    end

    it 'outro tipo de botão no lugar: indisponível' do
      aprovado_com([{ 'type' => 'PHONE_NUMBER', 'text' => 'Ver meu horário', 'phone_number' => '+5511999999999' }, parar])

      expect(garantir_link).to include(status: :indisponivel)
    end

    it 'pronto sem botões e modelo com botão: indisponível' do
      put_in_list(listed('APPROVED', 'components' => pronto.corpo.deep_stringify_keys['components'] +
                                                      [{ 'type' => 'BUTTONS', 'buttons' => [parar] }]))

      expect(garantir(criar: false)).to eq(status: :indisponivel, motivo: 'botoes_diferentes')
    end

    it 'FRONTEND_URL vazio: indisponível com o motivo, sem criar nada' do
      aprovado_com([url, parar])
      allow(client).to receive(:create)

      resultado = with_modified_env(FRONTEND_URL: '') { described_class.call(inbox: inbox, finalidade: :teste_link) }

      expect(resultado).to eq(status: :indisponivel, motivo: 'sem_base_url')
      expect(client).not_to have_received(:create)
    end

    it 'a URL do aprovado é comparada com a base do ambiente: outra base não serve' do
      aprovado_com([url, parar])

      expect(garantir_link).to include(status: :pronto)
      autonomia = with_modified_env(FRONTEND_URL: 'https://app.autonomia.site') do
        described_class.call(inbox: inbox, finalidade: :teste_link, criar: false)
      end
      expect(autonomia).to eq(status: :indisponivel, motivo: 'botoes_diferentes')
    end
  end

  it 'o modelo do sistema fica protegido na tela de Modelos' do
    expect(Whatsapp::Templates::SystemTemplates.owner_for(pronto.nome)).to eq('cobranca')
  end
end
