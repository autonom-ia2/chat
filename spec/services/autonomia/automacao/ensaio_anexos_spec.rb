require 'rails_helper'

# G20 (#2669) no ensaio: o passo de IA com `le: anexos` diz quantos anexos desta conversa a IA leria, ou o motivo de não
# ser chamada, como o motor. Não baixa o arquivo nem chama a IA.
RSpec.describe Autonomia::Automacao::Ensaio, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let!(:conversa) { create(:conversation, account: account, contact: contato, status: :resolved) }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise('o ensaio não baixa o anexo') # rubocop:disable RSpec/AnyInstance
  end

  def anexar(arquivo, tipo, content_type)
    mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: tipo)
    anexo.file.attach(io: Rails.root.join("spec/assets/#{arquivo}").open, filename: arquivo, content_type: content_type)
    anexo.save!
  end

  def no_do(passo)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
    described_class.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos].first
  end

  def resumir(leituras) = { 'id' => 'i1', 'tipo' => 'resumir', 'le' => leituras, 'linhas' => 2, 'destino' => 'nota' }

  it 'diz quantos anexos desta conversa a IA leria' do
    anexar('sample.pdf', :file, 'application/pdf')
    anexar('avatar.png', :image, 'image/png')

    expect(no_do(resumir(%w[anexos]))).to include(faria: 'ia_resumir', dados: { destino: 'nota', anexos: 2 })
  end

  it 'no decidir também, junto dos caminhos' do
    anexar('sample.pdf', :file, 'application/pdf')
    decidir = { 'id' => 'd1', 'tipo' => 'decidir', 'le' => %w[anexos], 'pergunta' => 'Tem o perfil?', 'nenhum' => [],
                'caminhos' => [{ 'nome' => 'Sim', 'chave' => 'sim', 'descricao' => 'sim', 'passos' => [] },
                               { 'nome' => 'Não', 'chave' => 'nao', 'descricao' => 'não', 'passos' => [] }] }

    expect(no_do(decidir)).to include(faria: 'decidir', dados: { anexos: 1 })
  end

  it 'o anexo que não pode ir à IA vira o motivo, como no motor' do
    anexar('contacts.csv', :file, 'text/csv')

    expect(no_do(resumir(%w[anexos]))[:dados]).to eq(destino: 'nota', anexos_motivo: 'anexo_fora_do_formato')
  end

  it 'sem pedir os anexos, o ensaio fica como era' do
    anexar('sample.pdf', :file, 'application/pdf')

    expect(no_do(resumir(%w[mensagens_recentes]))[:dados]).to eq(destino: 'nota')
  end
end
