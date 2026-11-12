require 'rails_helper'

# #2931, #2935 e #2936: o salvar (esquema + Receita) e o ensaio da aprovação, da reunião e da pesquisa. O ensaio diz o
# que fariam pelas mesmas perguntas do motor e não faz nada: nenhuma mensagem, nenhum pedido, nenhum aviso.
RSpec.describe Autonomia::Automacao::PassosQueEsperam, :automacao_motor do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:gerente) { create(:user, account: account, role: :administrator, name: 'Gerente Ana') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }

  before do
    # A conversa que o ensaio lê (a última da conta).
    create(:conversation, account: account, inbox: inbox, contact: contato, status: :resolved)
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia', 'automacao_passos_novos')
  end

  def aprovacao(extra = {})
    { 'id' => 'aprova', 'tipo' => 'pedir_aprovacao', 'quem' => { 'de' => 'pessoa', 'id' => gerente.id }, 'pergunta' => ['Pode seguir?'],
      'prazo' => { 'valor' => 1, 'unidade' => 'dias' }, 'aprovado' => [esperar_passo('depois')] }.merge(extra)
  end

  def pesquisa(extra = {})
    { 'id' => 'nota', 'tipo' => 'pesquisa_nota', 'pergunta' => 'De 0 a 10?', 'baixa_ate' => 6, 'alta_desde' => 9,
      'intervalo_dias' => 30, 'espera' => { 'valor' => 2, 'unidade' => 'dias' } }.merge(extra)
  end

  def receita(*passos, gatilho: { 'tipo' => 'conversa.resolvida' }) = { 'gatilho' => gatilho, 'passos' => passos }

  def problemas(receita)
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account.account_users.find_by(user: admin)).problemas
  end

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  describe 'o esquema' do
    it 'aceita os três como a tela monta e recusa o que a tela não deixa', :aggregate_failures do
      reuniao = { 'id' => 'r', 'tipo' => 'marcar_reuniao', 'com' => { 'de' => 'responsavel' }, 'duracao' => 30, 'convite' => 'Oi!',
                  'espera' => { 'valor' => 1, 'unidade' => 'dias' } }
      valido = ->(passo) { Autonomia::Automacao::Receita.esquema_valido?(receita(passo)) }

      expect([aprovacao, pesquisa, reuniao].map(&valido)).to all(be(true))
      expect(valido.call(reuniao.merge('com' => { 'de' => 'time', 'id' => 3 }))).to be(false)
      expect(valido.call(reuniao.merge('duracao' => 20))).to be(false)
      expect(valido.call(aprovacao('quem' => { 'de' => 'pessoa' }))).to be(false)
      expect(valido.call(pesquisa('intervalo_dias' => 10))).to be(false)
    end
  end

  describe 'ao salvar' do
    it 'sem a flag dos passos novos, recusa com o porquê' do
      account.disable_features!('automacao_passos_novos')

      expect(problemas(receita(aprovacao))).to include(frase(:passos_novos_desligados, passo: 'aprova'))
    end

    it 'a pesquisa com a nota média vazia é recusada' do
      expect(problemas(receita(pesquisa('baixa_ate' => 8, 'alta_desde' => 9)))).to include(frase(:pesquisa_faixa_media_vazia, passo: 'nota'))
    end

    it 'a pessoa de outra conta não aprova' do
      de_fora = create(:user)

      expect(problemas(receita(aprovacao('quem' => { 'de' => 'pessoa', 'id' => de_fora.id }))))
        .to include(frase(:pessoa_de_fora, passo: 'aprova', id: de_fora.id))
    end

    it 'a pesquisa precisa de conversa: no gatilho de contato, recusa' do
      gatilho = { 'tipo' => 'contato.data', 'campo' => 'aniversario', 'quando' => 'antes', 'dias' => 0, 'hora' => 9 }
      account.enable_features!('automacao_gatilhos')

      expect(problemas(receita(pesquisa, gatilho: gatilho))).to include(frase(:espera_resposta_sem_conversa, passo: 'nota'))
    end

    it 'o texto do pedido passa pela régua dos valores' do
      lido = problemas(receita(aprovacao('pergunta' => ['Valor: ', { '$valor' => 'conversa.inexistente' }])))

      expect(lido).to include(frase(:valor_desconhecido, passo: 'aprova', caminho: 'conversa.inexistente'))
    end

    it 'os três prontos passam' do
      expect(problemas(receita(aprovacao, pesquisa))).to be_empty
    end
  end

  describe 'no ensaio' do
    def passos_do_ensaio(receita)
      Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos]
    end

    it 'a aprovação diz a quem o pedido iria e abre os três galhos, sem pedido nem aviso', :aggregate_failures do
      no = nil
      expect { no = passos_do_ensaio(receita(aprovacao)).first }.not_to change(Notification, :count)

      expect(no).to include(faria: 'pedir_aprovacao', dados: { para: ['Gerente Ana'] })
      expect(no[:ramos].pluck(:chave)).to eq(%w[aprovado recusado ninguem_respondeu])
      expect(no[:ramos].first[:passos].first).to include(id: 'depois')
      expect(Autonomia::Automacao::Registro.count).to eq(0)
    end

    it 'a pesquisa mostra a pergunta e o prazo, sem mandar nada', :aggregate_failures do
      no = nil
      expect { no = passos_do_ensaio(receita(pesquisa)).first }.not_to change(Message, :count)

      expect(no).to include(faria: 'pesquisa_nota')
      expect(no[:dados]).to include(pergunta: 'De 0 a 10?', espera: { 'valor' => 2, 'unidade' => 'dias' })
    end

    it 'a pesquisa recente pula e segue para o passo seguinte' do
      contato.update!(additional_attributes: { 'pesquisa_perguntada_em' => 1.day.ago.iso8601 })

      lido = passos_do_ensaio(receita(pesquisa, esperar_passo('seguinte')))
      expect(lido.pluck(:id, :faria)).to eq([%w[nota pesquisa_recente], %w[seguinte esperar]])
    end
  end
end
