require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacunas G35 e G36 (#2679): a IA lê o card (`le: card`) e as notas internas da
# conversa (`le: notas`). Provadas em dois passos dos termos de aceite, montados pela API da tela, com a IA no dublê do
# endereço da OpenAI:
# - exemplo 15, passo 9 ("Cliente grande"): o card perdido, e a IA resume para o Carlos o motivo, que está no card;
# - exemplo 5, passo 1 ("Revisão do carro"): o card ganho, e a IA tira da conversa e da nota do mecânico o que fazer na
#   próxima revisão, e grava no contato.
# O resto dos exemplos 5 e 15 fica no pendentes_spec até as outras lacunas fecharem.
RSpec.describe 'Fechamento #2414 · G35 e G36: a IA lê o card e a nota', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:dono) { create(:user, account: account, role: :administrator, name: 'Marcos') }
  let(:carlos) { create(:user, account: account, role: :agent, name: 'Carlos') }
  let(:cliente) { create(:contact, account: account, name: 'Paula', phone_number: '+5511900000015') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: cliente, source_id: '5511900000015') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: cliente, contact_inbox: contact_inbox, status: :open) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: dono) }
  let(:card) do
    funil, etapa = funil_e_etapa
    account.crm_cards.create!(pipeline: funil, stage: etapa, inbox: canal.inbox, contact: cliente, primary_conversation: conversa,
                              title: 'Pedido de 300 uniformes', owner: carlos)
  end
  let(:roteiro) { {} }

  def ligar(nome, receita) = ligar_automacao(dono, account, montar_automacao(dono, account, nome: nome, receita: receita))

  def fechar_o_card(resultado, **campos)
    Crm::Cards::Closer.new(card: card, actor: dono, result: resultado, **campos).perform
    rodar_jobs
    perform_enqueued_jobs(only: Autonomia::Automacao::EventoDoCardJob)
    rodar_jobs
  end

  def pedido_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }.sole

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    [dono, carlos].each { |pessoa| create(:inbox_member, user: pessoa, inbox: canal.inbox) }
    create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: cliente,
                     content: 'Preciso dos uniformes até março.')
    card
    ia_responde(account, roteiro)
  end

  after { Current.reset }

  describe 'G35 · exemplo 15, passo 9: card perdido, a IA resume o motivo para o Carlos' do
    let(:roteiro) { { 'automacao_resumir' => { 'resumo' => 'Perdemos no preço: o concorrente fez 12% a menos.' } } }

    before do
      ligar('Cliente grande: perdido', gatilho: { tipo: 'card.perdido', funil_id: card.pipeline_id }, passos: [
              { id: 'motivo', tipo: 'resumir', le: %w[card mensagens_recentes], linhas: 2, destino: { avisar: { pessoas: [carlos.id] } } }
            ])
      clear_enqueued_jobs
    end

    it 'a IA recebe o card com o motivo da perda, e o Carlos é avisado no sino com o resumo', :aggregate_failures do
      fechar_o_card('lost', lost_reason: 'Concorrente fez preço 12% menor')

      lido = pedido_da_ia('automacao_resumir')['input'].to_json
      expect(lido).to include('Pedido de 300 uniformes', 'Concorrente fez preço 12% menor', 'Preciso dos uniformes até março.')
      aviso = conversa.messages.where(private: true).find_by('content LIKE ?', "%mention://user/#{carlos.id}/%")
      expect(aviso.content).to include('Perdemos no preço')
      expect(Notification.where(user: carlos, notification_type: 'conversation_mention').count).to eq(1)
    end
  end

  describe 'G36 · exemplo 5, passo 1: a IA lê a nota do mecânico junto da conversa e grava no contato' do
    let(:roteiro) { { 'automacao_extrair' => { 'proxima_revisao' => 'trocar as pastilhas de freio' } } }

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'proxima_revisao', attribute_display_name: 'Próxima revisão',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'text')
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :outgoing, private: true, sender: dono,
                       content: 'Mecânico: pastilhas no limite, trocar na próxima revisão.')
      ligar('Revisão: carro entregue', gatilho: { tipo: 'card.ganho', funil_id: card.pipeline_id }, passos: [
              { id: 'na_proxima', tipo: 'extrair', le: %w[mensagens_recentes notas],
                campos: [{ chave: 'proxima_revisao', descricao: 'o que fazer na próxima revisão, pela nota do mecânico',
                           destino: 'contato.atributos.proxima_revisao' }] }
            ])
      clear_enqueued_jobs
    end

    it 'a nota interna vai à IA como dado, e o que ela tirou fica no contato', :aggregate_failures do
      fechar_o_card('won')

      lido = pedido_da_ia('automacao_extrair')['input'].to_json
      expect(lido).to include('pastilhas no limite', 'Preciso dos uniformes até março.')
      expect(cliente.reload.custom_attributes).to include('proxima_revisao' => 'trocar as pastilhas de freio')
    end
  end
end
