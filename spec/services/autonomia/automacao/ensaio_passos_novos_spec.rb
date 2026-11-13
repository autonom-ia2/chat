require 'rails_helper'

# #2932–#2934 no ensaio: responde como o motor e não faz nada. A lista conta de verdade, o bloco mostra os passos dele e a
# busca nunca sai daqui (sem WebMock liberado, um pedido derrubaria o spec).
RSpec.describe Autonomia::Automacao::Ensaio, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
  let(:contato) { account.contacts.create!(name: 'Mercado Bom Preço', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }

  before do
    conversa
    ligar_motor(account)
    account.enable_features!('automacao_passos_novos')
  end

  def nos(*passos)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }
    described_class.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos]
  end

  def parar(id) = { 'id' => id, 'tipo' => 'parar' }

  it 'o "para cada" conta quem entraria hoje, sem o bloqueado, e mostra o galho sem rodar', :aggregate_failures do
    account.labels.create!(title: 'vip')
    %w[Ana Bruno Carla].each { |nome| account.contacts.create!(name: nome).update!(label_list: ['vip']) }
    account.contacts.find_by(name: 'Carla').update!(blocked: true)

    lista, = nos({ 'id' => 'lista', 'tipo' => 'repetir_lista', 'lista' => { 'de' => 'etiqueta', 'etiqueta' => 'vip' }, 'teto' => 1,
                   'ritmo' => 'aos_poucos', 'cada' => [parar('c1')] })

    expect(lista).to include(faria: 'repetir_lista', ramos: [{ chave: 'cada', passos: [{ id: 'c1', tipo: 'parar', faria: 'catalogo', dados: {} }] }])
    expect(lista[:dados]).to include(total: 1, fora_do_teto: 1, teto: 1)
    expect(Autonomia::Automacao::Execucao.count).to eq(0)
  end

  it 'a busca não sai do ensaio: diz os nomes que guardaria e mostra os dois caminhos', :aggregate_failures do
    busca, = nos({ 'id' => 'busca', 'tipo' => 'consultar', 'fonte' => { 'de' => 'endereco', 'url' => 'https://loja.exemplo.com/x' },
                   'guardar' => [{ 'nome' => 'Status', 'caminho' => 'status' }], 'nao_consultou' => [parar('nao')] }, parar('fim'))

    expect(busca).to include(faria: 'consultar', dados: { guardaria: ['Status'] })
    expect(busca[:ramos].map { |ramo| [ramo[:chave], ramo[:passos].pluck(:id)] }).to eq([['consultou', ['fim']], ['nao_consultou', ['nao']]])
    expect(busca.to_json).not_to include('loja.exemplo.com')
  end

  it 'a consulta pronta diz o que usaria desta conversa, sem buscar; o dado vazio volta vazio', :aggregate_failures do
    pronta = lambda do |partes|
      { 'id' => 'busca', 'tipo' => 'consultar', 'guardar' => [{ 'nome' => 'Rua', 'caminho' => 'logradouro' }],
        'fonte' => { 'de' => 'pronta', 'consulta' => 'cep', 'entradas' => { 'cep' => partes } } }
    end

    busca, = nos(pronta.call([{ '$valor' => 'contato.nome' }]), parar('fim'))
    expect(busca[:dados]).to eq(guardaria: ['Rua'], entradas: { 'cep' => 'Mercado Bom Preço' })

    vazia, = nos(pronta.call([{ '$valor' => 'contato.email' }]), parar('fim'))
    expect(vazia[:dados][:entradas]).to eq('cep' => nil)
  end

  it 'o bloco entra com os passos dele, cada um marcado com o bloco; o que sumiu diz por que pularia', :aggregate_failures do
    bloco = create(:autonomia_automacao, account: account, bloco: true)
    bloco.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [parar('b1')] }, autor: admin)

    usar, = nos({ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco.id })
    sumiu, = nos({ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => 999_999 })

    expect(usar).to include(faria: 'usar_bloco', dados: { nome: bloco.nome })
    expect(usar[:ramos].first[:passos]).to eq([{ bloco: bloco.id, id: 'b1', tipo: 'parar', faria: 'parar', dados: {} }])
    expect(sumiu[:faria]).to eq('bloco_sumiu')
  end

  it 'com a flag desligada, diz que o passo não está disponível' do
    account.disable_features!('automacao_passos_novos')

    expect(nos({ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => 1 }).first[:faria]).to eq('passos_novos_desligados')
  end
end
