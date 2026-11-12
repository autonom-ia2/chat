require 'rails_helper'

# Os gatilhos de etiqueta posta ou tirada (G10) e de troca de quem atende a conversa (F8.3) no Ensaio: na conversa ou
# no contato, como se o fato acontecesse agora. Com a etiqueta escolhida, só os que a têm, sem diferença de maiúscula,
# como o gatilho casa. O contato não tem conversa própria: segue a regra do card sem conversa (#2680). Nada é gravado
# nem mandado.
RSpec.describe Autonomia::Automacao::Ensaio, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:maria) { create(:contact, account: account, name: 'Maria') }
  let(:joao) { create(:contact, account: account, name: 'João') }
  let!(:com_vip) { create(:conversation, account: account, inbox: inbox, contact: maria) }
  let!(:sem_vip) { create(:conversation, account: account, inbox: inbox, contact: joao) }
  let(:ola) { mensagem_passo('p1', 'Oi ', { '$valor' => 'contato.nome' }) }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    create(:label, account: account, title: 'vip')
    com_vip.update_labels(%w[vip])
  end

  def receita(*passos, gatilho:) = { 'gatilho' => gatilho, 'passos' => passos }

  def ensaio(receita, conversa_id: nil)
    described_class.new(receita: receita, conta: account, usuario: admin, conversa_id: conversa_id).resultado
  end

  it 'aceita os quatro gatilhos novos de conversa e a etiqueta no contato; a data do contato ainda não', :aggregate_failures do
    %w[conversa.responsavel_mudou conversa.time_mudou conversa.etiqueta_posta conversa.etiqueta_tirada].each do |tipo|
      expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => tipo }))).to be(true)
      expect(described_class.alvo(receita(gatilho: { 'tipo' => tipo }))).to eq('conversa')
    end
    %w[contato.etiqueta_posta contato.etiqueta_tirada].each do |tipo|
      expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => tipo }))).to be(true)
      expect(described_class.alvo(receita(gatilho: { 'tipo' => tipo }))).to eq('contato')
    end
    expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => 'contato.data' }))).to be(false)
  end

  it 'troca da pessoa ou do time: nas conversas recentes, como se trocasse agora', :aggregate_failures do
    %w[conversa.responsavel_mudou conversa.time_mudou].each do |tipo|
      resultado = ensaio(receita(ola, gatilho: { 'tipo' => tipo }))

      expect(resultado[:alvo]).to eq('conversa')
      expect(resultado[:conversas].pluck(:conversa_id)).to contain_exactly(com_vip.display_id, sem_vip.display_id)
      expect(resultado[:conversas].pluck(:entraria)).to all(be(true))
    end
  end

  it 'etiqueta na conversa: só as que têm a etiqueta escolhida, sem diferença de maiúscula', :aggregate_failures do
    %w[conversa.etiqueta_posta conversa.etiqueta_tirada].each do |tipo|
      itens = ensaio(receita(ola, gatilho: { 'tipo' => tipo, 'etiqueta' => 'VIP' }))[:conversas]

      expect(itens.pluck(:conversa_id)).to eq([com_vip.display_id])
      expect(itens.first[:passos].first[:dados][:texto]).to eq('Oi Maria')
    end
    expect(ensaio(receita(ola, gatilho: { 'tipo' => 'conversa.etiqueta_posta' }))[:conversas].size).to eq(2)
  end

  it 'a conversa escolhida sem a etiqueta é como se não existisse' do
    expect { ensaio(receita(ola, gatilho: { 'tipo' => 'conversa.etiqueta_posta', 'etiqueta' => 'vip' }), conversa_id: sem_vip.display_id) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  describe 'etiqueta no contato' do
    let(:caixa) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
    let(:passos) { [ola, esperar_passo('p2')] }

    before { maria.update_labels(%w[vip]) }

    def faria(gatilho)
      ensaio(receita(*passos, gatilho: gatilho))[:conversas].first[:passos].to_h { |no| [no[:id], no[:faria]] }
    end

    it 'só os contatos com a etiqueta, pelo id e pelo nome', :aggregate_failures do
      %w[contato.etiqueta_posta contato.etiqueta_tirada].each do |tipo|
        resultado = ensaio(receita(*passos, gatilho: { 'tipo' => tipo, 'etiqueta' => 'Vip' }))

        expect(resultado[:alvo]).to eq('contato')
        expect(resultado[:conversas].map { |item| item.slice(:conversa_id, :nome, :entraria) })
          .to eq([{ conversa_id: maria.id, nome: 'Maria', entraria: true }])
      end
    end

    it 'sem a caixa da conversa nova: a mensagem pula, como no card sem conversa' do
      expect(faria({ 'tipo' => 'contato.etiqueta_posta', 'etiqueta' => 'vip' })).to eq('p1' => 'sem_conversa', 'p2' => 'esperar')
    end

    it 'com a caixa: a mensagem abriria a conversa nela, sem gravar nada', :aggregate_failures do
      gatilho = { 'tipo' => 'contato.etiqueta_posta', 'etiqueta' => 'vip', 'conversa_nova' => { 'caixa_id' => caixa.id } }
      no = ensaio(receita(*passos, gatilho: gatilho))[:conversas].first[:passos].first

      expect(no).to include(faria: 'mensagem')
      expect(no[:dados]).to include(texto: 'Oi Maria', conversa_nova: caixa.name)
      expect { ensaio(receita(*passos, gatilho: gatilho)) }.not_to(change { [Conversation.count, ContactInbox.count, Message.count] })
    end

    it 'o contato escolhido sem a etiqueta é como se não existisse' do
      expect { ensaio(receita(*passos, gatilho: { 'tipo' => 'contato.etiqueta_tirada', 'etiqueta' => 'vip' }), conversa_id: joao.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
