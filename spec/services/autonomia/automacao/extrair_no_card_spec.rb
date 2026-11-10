require 'rails_helper'

# G70 (#2880), decisão 20 do Rodrigo (10/11, "IA só anota campos"): o "extrair" preenche campos do card. O card é o
# alvo (gatilho de card) ou, numa conversa, o card dela, que fora isso continua só para ler (decisão 19): fechar, mover,
# trocar o dono e `card.id` em caminho ou corpo seguem recusados. O valor protegido nunca é destino (decisão 9).
RSpec.describe 'Automação livre · o extrair grava no card (G70)', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Vanessa') }
  let(:contato) { create(:contact, account: account, name: 'Ana', phone_number: '+5511999990070') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    Crm::Cards::Creator.new(account: account, user: admin, params: { pipeline_id: funil.first.id, stage_id: funil.last.id,
                                                                     contact_id: contato.id, conversation_id: conversa.id,
                                                                     title: 'Black da Ana' }).perform
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    %w[peca tamanho].each do |chave|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_model: 'card_attribute',
                                           attribute_display_type: 'text')
    end
    { 'vendedora' => 'pessoa', 'indicado_por' => 'contato' }.each do |chave, tipo|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_model: 'card_attribute',
                                           attribute_display_type: tipo)
    end
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Quero o vestido no M')
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'r1', output_text: { 'peca' => 'vestido', 'tamanho' => 'M' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }.to_json
    )
  end

  after { Current.reset }

  def extrair(destinos = { 'peca' => 'card.atributos.peca', 'tamanho' => 'card.atributos.tamanho' })
    { 'id' => 'p1', 'tipo' => 'extrair', 'le' => %w[mensagens_recentes],
      'campos' => destinos.map { |chave, destino| { 'chave' => chave, 'descricao' => "a #{chave}", 'destino' => destino } } }
  end

  def rodar(definicao, alvo, chave_gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: chave_gatilho).call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last
  end

  def problemas(passos, gatilho: { 'tipo' => 'mensagem.criada' })
    quem = AccountUser.find_by(account: account, user: admin)
    Autonomia::Automacao::Receita.new({ 'gatilho' => gatilho, 'passos' => passos }, conta: account, account_user: quem).problemas
  end

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: 'p1', **valores)

  it 'na conversa, grava os campos no card dela, como quem ligou', :aggregate_failures do
    card
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = rodar(definicao, conversa, 'mensagem.criada')

    expect(card.reload.custom_attributes).to include('peca' => 'vestido', 'tamanho' => 'M')
    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p1').dados['campos'])
      .to include('gravados' => %w[peca tamanho], 'ausentes' => [])
  end

  it 'no gatilho de card, grava no próprio card (o alvo)' do
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil.first.id })

    rodar(definicao, card, 'card.ganho')

    expect(card.reload.custom_attributes).to include('peca' => 'vestido', 'tamanho' => 'M')
  end

  it 'a conversa sem card: nada a gravar, os campos ficam ausentes e o passo pula com o motivo', :aggregate_failures do
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = rodar(definicao, conversa, 'mensagem.criada')

    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p1'))
      .to have_attributes(resultado: 'pulado', motivo: 'dado_ausente')
  end

  describe 'ao salvar' do
    it 'aceita campo do card na conversa e no card; recusa no contato, no campo de gente (pessoa, contato) e no valor', :aggregate_failures do
      expect(problemas([extrair])).to be_empty
      expect(problemas([extrair], gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil.first.id })).to be_empty
      expect(problemas([extrair], gatilho: { 'tipo' => 'contato.criado' })).to include(frase(:destino_card_sem_card))
      %w[vendedora indicado_por].each do |gente|
        expect(problemas([extrair(gente => "card.atributos.#{gente}")])).to include(frase(:destino_invalido, destino: "card.atributos.#{gente}"))
      end
      expect(problemas([extrair('valor' => 'card.valor')])).to include(frase(:destino_invalido, destino: 'card.valor'))
      expect(problemas([extrair('cor' => 'card.atributos.cor')])).to include(frase(:destino_invalido, destino: 'card.atributos.cor'))
    end

    it 'o campo do card no extrair conta como mexer no card: pede a chave de funis (quem salva e quem ligou)' do
      receita = { 'gatilho' => { 'tipo' => 'mensagem.criada' }, 'passos' => [extrair] }

      expect(Autonomia::Automacao::CardDaConversa.le?(receita)).to be(true)
      expect(Autonomia::Automacao::CardDaConversa.le?(receita.merge('passos' => [extrair('peca' => 'conversa.atributos.peca')])))
        .to be(false)
    end

    # O outro lado da decisão 20: fora o extrair, o card da conversa segue só para ler.
    it 'fechar, mover, trocar o dono e card.id em caminho ou corpo seguem recusados na conversa', :aggregate_failures do
      fechar = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/close', 'descricao' => 'Fechar',
                 'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'result' => 'won' } }
      mover = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover',
                'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'stage_id' => funil.last.id } }
      dono = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Dono',
               'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'card' => { 'owner_id' => admin.id } } }

      recusa = frase(:card_da_conversa_so_le, caminho: 'card.id')
      [fechar, mover, dono].each { |passo| expect(problemas([passo])).to include(recusa) }
      expect(Autonomia::Automacao::CardDaConversa.problema('card.id', :corpo, 'Conversation')).to eq(:card_da_conversa_so_le)
    end
  end
end
