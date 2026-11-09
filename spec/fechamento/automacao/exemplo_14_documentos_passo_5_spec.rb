require 'rails_helper'

# Fechamento do épico #2414 (#2570), exemplo 14 ("Documentação completa para emitir"), passo 5, à risca (G46):
# "2 dias sem documento novo: lembra uma vez, pelo modelo aprovado. 4 dias: cria retorno para o corretor ligar."
# Documento é "foto ou PDF" (passo 2). São duas automações no gatilho de tempo card.sem_documento, na etapa
# "Documentação", montadas e ligadas pela API da tela:
# - A: 2 dias, a mensagem pelo modelo aprovado;
# - B: 4 dias, o retorno para o responsável do card (o corretor).
# A conta começa na entrada na etapa e recomeça a cada foto ou PDF; texto e áudio ("já mando") não recomeçam. A
# varredura de tempo roda como em produção (TempoJob, a cada 15 minutos), e o modelo para no receptor do WhatsApp
# oficial. "Lembra uma vez" é uma vez a cada silêncio: o documento seguinte conta de novo (pergunta aberta no PR).
RSpec.describe 'Fechamento #2414 · exemplo 14, passo 5: sem documento novo', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:cida) { create(:user, account: account, role: :administrator, name: 'Dona Cida') }
  let(:corretor) { create(:user, account: account, role: :agent, name: 'Rafael Corretor') }
  let(:marcos) { create(:contact, account: account, name: 'Marcos', phone_number: '+5511900002714') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: marcos, source_id: '5511900002714')
    create(:conversation, account: account, inbox: inbox, contact: marcos, contact_inbox: contact_inbox, status: :open)
  end
  let(:funil) { create_crm_pipeline(account: account, user: cida, name: 'Seguros').first }
  let(:documentacao) { create_crm_stage(account: account, pipeline: funil, name: 'Documentação', position: 1) }
  let(:emissao) { create_crm_stage(account: account, pipeline: funil, name: 'Emissão', position: 2) }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def inicio = fuso.parse('2026-11-09 09:00')

  def lembrete
    { id: 'lembrete', tipo: 'mensagem', texto: ['Lembrete dos documentos'],
      modelo: { nome: 'lembrete_documentos', idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }]] } }
  end

  # O termo não diz quando o corretor liga: o retorno pede um prazo, e o menor é 1 minuto.
  def retorno
    { id: 'ligar', tipo: 'retorno', titulo: ['Ligar para ', { '$valor' => 'contato.nome' }, ': documentos'],
      daqui: { valor: 1, unidade: 'minutos' } }
  end

  def ligada(nome, dias, passo, por: cida)
    receita = { gatilho: { tipo: 'card.sem_documento', etapa_id: documentacao.id, dias: dias }, passos: [passo] }
    automacao = montar_automacao(por, account, nome: nome, receita: receita)
    ligar_automacao(por, account, automacao)
    clear_enqueued_jobs
    automacao
  end

  # Um job por vez, como no Sidekiq, com o do evento do card no meio.
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  # O começo do exemplo: o card entra em "Documentação", com a conversa do WhatsApp e o corretor como responsável.
  def entra_em_documentacao
    Crm::Cards::Creator.new(account: account, user: cida, params: {
                              pipeline_id: funil.id, stage_id: documentacao.id, contact_id: marcos.id, owner_id: corretor.id,
                              conversation_id: conversa.id, inbox_id: inbox.id, title: 'Seguro auto do Marcos', currency: 'BRL'
                            }).perform
    drenar
    account.crm_cards.find_by!(title: 'Seguro auto do Marcos')
  end

  # O tipo do anexo, o content type, o arquivo de spec/assets, o nome e o meta de cada mídia que o Marcos manda.
  def midias
    {
      cnh: [:image, 'image/png', 'sample.png', 'cnh.png', {}],
      crlv: [:file, 'application/pdf', 'sample.pdf', 'crlv.pdf', {}],
      audio: [:audio, 'audio/ogg', 'sample.ogg', 'ja-mando.ogg', {}],
      figurinha: [:image, 'image/webp', 'sample.png', 'figurinha.webp', { 'is_sticker' => true }],
      docx: [:file, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'sample.pdf', 'proposta.docx', {}]
    }
  end

  # A mídia chega como o canal grava: a mensagem sem texto, com o arquivo anexado.
  def cliente_manda(midia, quando:, onde: conversa)
    file_type, content_type, arquivo, nome, meta = midias.fetch(midia)
    travel_to(quando) do
      mensagem = onde.messages.new(account: account, inbox: onde.inbox, message_type: :incoming, sender: marcos, content: nil)
      anexo = mensagem.attachments.new(account_id: account.id, file_type: file_type, meta: meta)
      anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: nome, content_type: content_type, identify: false)
      mensagem.save!
      drenar
    end
  end

  # A varredura dos gatilhos de tempo naquele instante e os jobs que ela abre.
  def varre(instante)
    travel_to(instante) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      drenar
    end
  end

  def lembretes = chamadas_para('graph.facebook.com').count { |chamada| chamada.corpo.dig('template', 'name') == 'lembrete_documentos' }

  before do
    travel_to(inicio)
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    [cida, corretor].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
    canal.update!(message_templates: [{ 'name' => 'lembrete_documentos', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                        'category' => 'UTILITY',
                                        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, ainda faltam documentos.' }] }])
    receptor_whatsapp_cloud
    [documentacao, emissao]
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: marcos,
                     content: 'Fechado, pode fazer o seguro')
    clear_enqueued_jobs
  end

  after { Current.reset }

  describe 'as duas automações ligadas antes de o card entrar' do
    let!(:automacao_a) { ligada('Lembrete dos documentos', 2, lembrete) }
    let!(:automacao_b) { ligada('Corretor liga', 4, retorno) }
    let!(:card) { entra_em_documentacao }

    def entrada = card.reload.entered_stage_at

    it 'silêncio desde a entrada: lembra uma vez no 2º dia e cria o retorno no 4º', :aggregate_failures do
      varre(entrada + 1.day + 10.minutes)
      expect(lembretes).to eq(0)

      varre(entrada + 2.days + 10.minutes)
      expect(lembretes).to eq(1)
      expect(historico_de(automacao_a)).to eq([['lembrete', 'ok', nil]])
      expect(chamadas_para('graph.facebook.com').last.corpo.dig('template', 'components', 0, 'parameters'))
        .to eq([{ 'type' => 'text', 'text' => 'Marcos' }])

      # "Uma vez": as rodadas seguintes no mesmo silêncio não mandam de novo.
      varre(entrada + 2.days + 25.minutes)
      varre(entrada + 3.days)
      expect(lembretes).to eq(1)
      expect(Crm::FollowUp.count).to eq(0)

      varre(entrada + 4.days + 10.minutes)
      expect(historico_de(automacao_b)).to eq([['ligar', 'ok', nil]])
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, conversation_id: conversa.id, recipient_mode: 'card_owner',
                                                    title: 'Ligar para Marcos: documentos', status: 'pending')
      expect(lembretes).to eq(1)
    end

    it '"já mando" por texto ou áudio não zera a conta, nem figurinha ou arquivo que não é PDF', :aggregate_failures do
      travel_to(entrada + 1.day) { cliente_escreve(conversa, 'Já mando os documentos') }
      %i[audio figurinha docx].each_with_index { |midia, minuto| cliente_manda(midia, quando: entrada + 1.day + (minuto + 1).minutes) }

      varre(entrada + 2.days + 10.minutes)
      expect(lembretes).to eq(1)
      expect(historico_de(automacao_a)).to eq([['lembrete', 'ok', nil]])
    end

    it 'documento novo recomeça a conta: a CNH adia o lembrete, e o PDF depois abre outro silêncio', :aggregate_failures do
      cnh = entrada + 1.day
      cliente_manda(:cnh, quando: cnh)

      varre(entrada + 2.days + 10.minutes)
      expect(lembretes).to eq(0)

      varre(cnh + 2.days + 10.minutes)
      expect(lembretes).to eq(1)
      varre(cnh + 3.days)
      expect(Crm::FollowUp.count).to eq(0)

      varre(cnh + 4.days + 10.minutes)
      expect(Crm::FollowUp.count).to eq(1)

      pdf = cnh + 4.days + 1.hour
      cliente_manda(:crlv, quando: pdf)
      varre(pdf + 1.day)
      expect(lembretes).to eq(1)

      varre(pdf + 2.days + 10.minutes)
      expect(lembretes).to eq(2)
      expect(historico_de(automacao_a)).to eq([['lembrete', 'ok', nil], ['lembrete', 'ok', nil]])
    end

    it 'o card que vai para "Emissão" antes do prazo não recebe nada', :aggregate_failures do
      travel_to(entrada + 1.day) do
        Crm::Cards::Mover.new(card: card, actor: cida, target_stage: emissao).perform
        drenar
      end

      varre(entrada + 2.days + 10.minutes)
      varre(entrada + 4.days + 10.minutes)
      expect(lembretes).to eq(0)
      expect(Crm::FollowUp.count).to eq(0)
    end
  end

  describe 'ligar não age no passado' do
    it 'o card parado há 3 dias quando a automação liga não dispara; o próximo documento conta', :aggregate_failures do
      card = entra_em_documentacao
      automacao = travel_to(card.entered_stage_at + 3.days) { ligada('Lembrete dos documentos', 2, lembrete) }

      varre(card.entered_stage_at + 3.days + 15.minutes)
      expect(lembretes).to eq(0)

      foto = card.entered_stage_at + 3.days + 1.hour
      cliente_manda(:cnh, quando: foto)
      varre(foto + 2.days + 10.minutes)
      expect(lembretes).to eq(1)
      expect(historico_de(automacao)).to eq([['lembrete', 'ok', nil]])
    end
  end

  # Quem liga é uma agente com a chave de funis, fora da caixa B. O PDF do mesmo contato que chega numa conversa da
  # caixa B não conta: documento numa caixa que ela não abre não decide nada (régua do Resposta.cliente?, #2680).
  describe 'filtro de acesso de quem ligou' do
    let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
    let(:funcao) do
      create(:custom_role, account: account,
                           permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards crm_manage_pipelines])
    end
    let(:caixa_b) { create(:inbox, account: account, name: 'Caixa B') }
    let(:conversa_b) { create(:conversation, account: account, inbox: caixa_b, contact: marcos, status: :open) }

    before do
      account.account_users.find_by(user: bia).update!(custom_role: funcao)
      create(:inbox_member, user: bia, inbox: inbox)
    end

    it 'o PDF numa conversa da caixa B não recomeça a conta, e o lembrete sai no prazo', :aggregate_failures do
      automacao = ligada('Lembrete dos documentos', 2, lembrete, por: bia)
      card = entra_em_documentacao
      cliente_manda(:crlv, quando: card.entered_stage_at + 1.day, onde: conversa_b)

      varre(card.entered_stage_at + 2.days + 10.minutes)
      expect(lembretes).to eq(1)
      expect(historico_de(automacao)).to eq([['lembrete', 'ok', nil]])
    end
  end
end
