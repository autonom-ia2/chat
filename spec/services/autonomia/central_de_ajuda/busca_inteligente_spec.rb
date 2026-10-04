require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::BuscaInteligente do
  # Cliente falso: guarda o que recebeu e devolve a resposta montada no teste. Nada sai para a rede.
  let(:cliente_falso) do
    Class.new do
      attr_reader :chamadas
      attr_accessor :resposta, :erro

      def initialize = @chamadas = []

      def evaluate(state:, questions:, model:)
        @chamadas << { state: state, questions: questions, model: model }
        raise erro if erro

        resposta
      end
    end.new
  end
  let(:dona) { create(:account) }
  let(:conta) { create(:account) }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:agente) { create(:user, account: conta, role: :agent) }
  let(:portal) { create(:portal, account: dona, slug: 'plataforma') }
  let(:sintomas) do
    "## O que é\n\nTexto.\n\n## O que dá errado\n\n- **\"A mensagem não chega\"** — confira o número.\n" \
      "- Item sem aspas não conta.\n- **\"Aparece desconectado\"** — leia o QR de novo.\n\n## Depois\n\n- **\"Fora da seção\"** — não conta.\n"
  end

  def artigo(id, titulo, publico: 'ambos', texto: 'Passo 1.')
    create(:article, portal: portal, account: dona, slug: "plataforma-#{id.tr('.', '-')}", title: titulo,
                     description: "Sobre #{titulo}", content: texto, status: :published,
                     meta: { 'central' => { 'id' => id, 'publico' => publico } })
  end

  def leitura_de(usuario, account: conta)
    Autonomia::CentralDeAjuda::Leitura.new(account: account, account_user: account.account_users.find_by(user: usuario))
  end

  def busca(usuario = agente, account: conta)
    described_class.new(leitura: leitura_de(usuario, account: account), account: account, client: cliente_falso, model: 'jev-1.13.0')
  end

  def responder(choice: '02.04', confidence: 0.82, model: 'jev-1.13.0', type: 'choice')
    cliente_falso.resposta = { 'model' => model, 'usage' => { 'input_tokens' => 20_000, 'output_tokens' => 2 },
                               'answers' => { 'artigo' => { 'type' => type, 'choice' => choice, 'confidence' => confidence } } }
  end

  before do
    allow(TypesafeAi::Config).to receive(:configured?).and_return(true)
    artigo('02.04', 'Conectar o WhatsApp', texto: sintomas)
    artigo('02.05', 'Seus avisos')
    artigo('03.01', 'Configurar a conta', publico: 'admin')
    responder
  end

  it 'escolhe o artigo e devolve o resumo dele com a certeza' do
    resultado = busca.melhor('  meu whatsapp não manda mensagem  ')

    expect(resultado[:artigo]).to include(id: '02.04', ref: '02-04', titulo: 'Conectar o WhatsApp')
    expect(resultado[:certeza]).to eq(0.82)
  end

  it 'pergunta na forma medida: escolha com a frase da pessoa como estado e um critério por artigo, mais nenhum' do
    busca.melhor('meu whatsapp não manda mensagem')

    chamada = cliente_falso.chamadas.sole
    pergunta = chamada[:questions]['artigo']
    expect(chamada[:model]).to eq('jev-1.13.0')
    expect(chamada[:state]).to eq('pergunta_da_pessoa' => 'meu whatsapp não manda mensagem')
    expect(pergunta[:type]).to eq('choice')
    expect(pergunta[:instructions]).to eq(described_class::INSTRUCOES)
    expect(pergunta[:criteria]['nenhum']).to eq('Nenhum artigo da lista responde ao que a pessoa escreveu.')
    expect(pergunta[:criteria]['02.05']).to eq('Seus avisos. Sobre Seus avisos')
  end

  it 'soma à descrição os sintomas do "O que dá errado", só os da seção e só os entre aspas' do
    busca.melhor('whatsapp desconectado')

    expect(cliente_falso.chamadas.sole[:questions]['artigo'][:criteria]['02.04']).to eq(
      'Conectar o WhatsApp. Sobre Conectar o WhatsApp Problemas comuns: A mensagem não chega; Aparece desconectado'
    )
  end

  it 'corta a descrição em 600 caracteres' do
    artigo('02.06', 'Longo', texto: "## O que dá errado\n\n- **\"#{'x' * 700}\"** — fim.\n")

    expect(cliente_falso.tap { busca.melhor('longo demais') }.chamadas.sole[:questions]['artigo'][:criteria]['02.06'].length).to eq(600)
  end

  it 'manda só os artigos que a pessoa pode ler: o de administrador some para quem atende' do
    busca(agente).melhor('configurar conta')
    busca(admin).melhor('configurar conta')

    para_agente, para_admin = cliente_falso.chamadas.map { |chamada| chamada[:questions]['artigo'][:criteria].keys }
    expect(para_agente).to eq(%w[02.04 02.05 nenhum])
    expect(para_admin).to eq(%w[02.04 02.05 03.01 nenhum])
  end

  it 'devolve nil quando o Jev diz que nenhum artigo responde' do
    responder(choice: 'nenhum', confidence: 0.9)

    expect(busca.melhor('boleto vencido')).to be_nil
  end

  it 'recusa escolha fora das chaves (inclusive artigo que a pessoa não pode ler)' do
    responder(choice: '03.01')

    expect(busca(agente).melhor('configurar conta')).to be_nil
  end

  it 'recusa certeza que não é número entre 0 e 1, tipo errado e modelo diferente' do
    [{ confidence: 1.5 }, { confidence: '0.9' }, { confidence: Float::NAN }, { type: 'noul' }, { model: 'jev-9' }].each do |troca|
      responder(**troca)
      expect(busca.melhor("pergunta #{troca}")).to be_nil
    end
  end

  it 'devolve nil para resposta sem os campos esperados' do
    cliente_falso.resposta = { 'model' => 'jev-1.13.0', 'answers' => {} }

    expect(busca.melhor('whatsapp')).to be_nil
  end

  it 'devolve nil quando o cliente falha e registra só o código e o tamanho do termo' do
    cliente_falso.erro = TypesafeAi::Client::Error.new('typesafe_unavailable')
    allow(Rails.logger).to receive(:warn)

    expect(busca.melhor('whatsapp sigiloso')).to be_nil
    expect(Rails.logger).to have_received(:warn).with(include('code=typesafe_unavailable').and(include('tamanho_do_termo=17')))
    expect(Rails.logger).not_to have_received(:warn).with(include('sigiloso'))
  end

  it 'não chama o Jev sem a chave configurada' do
    allow(TypesafeAi::Config).to receive(:configured?).and_return(false)

    expect(busca.melhor('whatsapp')).to be_nil
    expect(cliente_falso.chamadas).to be_empty
  end

  it 'não chama o Jev com termo vazio ou de menos de 3 letras' do
    expect([nil, '', '   ', ' ab '].map { |termo| busca.melhor(termo) }).to all(be_nil)
    expect(cliente_falso.chamadas).to be_empty
  end

  it 'registra o custo de cada chamada real com a feature central_busca, na conta de quem buscou' do
    busca.melhor('whatsapp')

    evento = Crm::AiUsageEvent.sole
    expect(evento).to have_attributes(account_id: conta.id, feature: 'central_busca', model: 'jev-1.13.0',
                                      input_tokens: 20_000, output_tokens: 2)
  end

  describe 'cache' do
    around do |exemplo|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      exemplo.run
    ensure
      Rails.cache = original
    end

    it 'repete a resposta para o mesmo termo, sem acento, maiúscula nem espaço a mais, sem pagar de novo' do
      busca.melhor('Não  CONECTA')
      resultado = busca.melhor('nao conecta')

      expect(resultado[:artigo][:id]).to eq('02.04')
      expect(cliente_falso.chamadas.size).to eq(1)
      expect(Crm::AiUsageEvent.count).to eq(1)
    end

    it 'guarda também o "nenhum"' do
      responder(choice: 'nenhum')

      2.times { expect(busca.melhor('boleto vencido')).to be_nil }
      expect(cliente_falso.chamadas.size).to eq(1)
    end

    it 'não guarda erro: a próxima busca pergunta de novo' do
      cliente_falso.erro = TypesafeAi::Client::Error.new('typesafe_unavailable')
      busca.melhor('whatsapp')
      cliente_falso.erro = nil

      expect(busca.melhor('whatsapp')[:artigo][:id]).to eq('02.04')
      expect(cliente_falso.chamadas.size).to eq(2)
    end

    it 'não guarda resposta inválida' do
      responder(choice: 'inventado')
      busca.melhor('whatsapp')
      responder

      expect(busca.melhor('whatsapp')).to be_present
      expect(cliente_falso.chamadas.size).to eq(2)
    end

    it 'não reaproveita entre quem vê artigos diferentes: o administrador pergunta de novo' do
      responder(choice: '03.01')
      expect(busca(admin).melhor('configurar conta')[:artigo][:id]).to eq('03.01')

      expect(busca(agente).melhor('configurar conta')).to be_nil
      expect(cliente_falso.chamadas.size).to eq(2)
      expect(cliente_falso.chamadas.last[:questions]['artigo'][:criteria]).not_to have_key('03.01')
    end

    it 'pergunta de novo quando o artigo muda' do
      busca.melhor('whatsapp')
      Article.find_by(slug: 'plataforma-02-05').update!(title: 'Seus avisos e alertas')
      busca.melhor('whatsapp')

      expect(cliente_falso.chamadas.size).to eq(2)
    end

    it 'não divide a resposta entre termos que só diferem em caractere sem equivalente (emoji)' do
      busca.melhor('whatsapp 😡')
      busca.melhor('whatsapp 🙏')

      expect(cliente_falso.chamadas.size).to eq(2)
    end

    it 'pergunta de novo quando a instrução muda, sem depender de versão à mão' do
      busca.melhor('whatsapp')
      stub_const("#{described_class}::INSTRUCOES", 'Outra forma de perguntar.')
      busca.melhor('whatsapp')

      expect(cliente_falso.chamadas.size).to eq(2)
    end

    it 'o teto de gasto só conta chamada real: resposta do cache não passa pelo limite' do
      limite = instance_double(Autonomia::CentralDeAjuda::LimiteDaBusca, permitir?: true)
      com_limite = described_class.new(leitura: leitura_de(agente), account: conta, limite: limite, client: cliente_falso,
                                       model: 'jev-1.13.0')

      2.times { com_limite.melhor('whatsapp') }

      expect(limite).to have_received(:permitir?).once
    end
  end

  describe 'teto de gasto' do
    it 'não chama o Jev quando o limite estourou, e registra só o código' do
      limite = instance_double(Autonomia::CentralDeAjuda::LimiteDaBusca, permitir?: false)
      allow(Rails.logger).to receive(:warn)
      com_limite = described_class.new(leitura: leitura_de(agente), account: conta, limite: limite, client: cliente_falso,
                                       model: 'jev-1.13.0')

      expect(com_limite.melhor('whatsapp')).to be_nil
      expect(cliente_falso.chamadas).to be_empty
      expect(Rails.logger).to have_received(:warn).with(include('code=limite'))
    end
  end
end
