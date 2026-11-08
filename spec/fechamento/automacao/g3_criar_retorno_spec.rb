require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G3: criar retorno para a equipe, com e sem a mensagem automática. Provado
# no passo 8 do exemplo 15 ("Card ganho: ... cria retorno de pós-venda para 15 dias"): a dona monta e liga pela API da
# tela, o card ganho sai pelo emissor do CRM, o despacho leva o evento ao motor e o retorno nasce no Followup como se
# ela o criasse na tela. O exemplo 15 inteiro fica no pendentes_spec até as outras lacunas dele fecharem.
RSpec.describe 'Fechamento #2414 · G3: criar retorno para a equipe', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:carlos) { create(:user, account: account, role: :administrator, name: 'Carlos Dono') }
  let(:vendedora) { create(:user, account: account, role: :agent, name: 'Bia Vendas') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [carlos, vendedora]) }
  let(:cliente) { account.contacts.create!(name: 'Mercado Bom Preço', phone_number: '+5511900000015') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: cliente) }
  let(:funil) { create_crm_pipeline(account: account, user: carlos).first }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil.stages.first, inbox: inbox, contact: cliente, primary_conversation: conversa,
                              title: 'Pedido de R$ 80 mil', currency: 'BRL', owner: vendedora)
  end

  let(:pos_venda) do
    { id: 'pos_venda', tipo: 'retorno', titulo: ['Pós-venda: ', { '$valor' => 'contato.nome' }],
      daqui: { valor: 15, unidade: 'dias' } }
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    card
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job por vez, como no Sidekiq, com o job do evento do card no meio.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def ligada_no_card_ganho(*passos)
    receita = { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: passos }
    automacao = montar_automacao(carlos, account, nome: 'Pós-venda do cliente grande', receita: receita)
    ligar_automacao(carlos, account, automacao)
    automacao
  end

  def ganhar_o_card
    Crm::Cards::Closer.new(card: card, actor: vendedora, result: 'won').perform
    drenar
  end

  it 'card ganho: o retorno de pós-venda nasce no card, para quem cuida, em 15 dias, como o Carlos', :aggregate_failures do
    automacao = ligada_no_card_ganho(pos_venda)

    freeze_time do
      ganhar_o_card

      expect(historico_de(automacao)).to eq([['pos_venda', 'ok', nil]])
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, conversation_id: conversa.id, title: 'Pós-venda: Mercado Bom Preço',
                                                    created_by_id: carlos.id, recipient_mode: 'card_owner',
                                                    automation_mode: 'reminder_only', status: 'pending', due_at: 15.days.from_now)
    end
  end

  it 'com a mensagem: o retorno manda sozinho, no dia, o texto com o nome do cliente', :aggregate_failures do
    create_incoming_message(conversation: conversa)
    automacao = ligada_no_card_ganho(pos_venda.merge(envio: { mensagem: ['Oi, ', { '$valor' => 'contato.nome' }, '! Tudo certo com o pedido?'] }))

    ganhar_o_card

    expect(historico_de(automacao)).to eq([['pos_venda', 'ok', nil]])
    expect(Crm::FollowUp.sole).to have_attributes(automation_mode: 'auto_send_message', follow_up_type: 'message')
    expect(Crm::FollowUp.sole.metadata['message_body']).to eq('Oi, Mercado Bom Preço! Tudo certo com o pedido?')
  end
end
