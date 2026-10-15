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
      put_in_list(listed('APPROVED', 'name' => 'boas_vindas'))
      allow(client).to receive(:create).and_return(outcome.new(template: listed('PENDING'), created: true))

      expect(garantir).to include(status: :em_analise)
      expect(client).to have_received(:create).once
    end
  end

  describe 'quando o modelo não está na lista da caixa' do
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

  it 'o modelo do sistema fica protegido na tela de Modelos' do
    expect(Whatsapp::Templates::SystemTemplates.owner_for(pronto.nome)).to eq('cobranca')
  end
end
