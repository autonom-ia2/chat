require 'rails_helper'

RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  def para(usuario)
    described_class.new(account: conta, user: usuario)
  end

  def responder(codigo, corpo = '{}')
    resposta = instance_double(Net::HTTPResponse, code: codigo, body: corpo)
    capturada = nil
    allow(Net::HTTP).to receive(:start) do |_host, _porta, _opcoes, &bloco|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |req|
        capturada = req
        resposta
      end
      bloco.call(http)
    end
    -> { capturada }
  end

  describe 'o catálogo' do
    # Lista escrita à mão nunca vira a plataforma: três ações não são a
    # plataforma, do mesmo jeito que cinco assuntos não eram a leitura.
    it 'nasce do roteador e cobre a plataforma inteira' do
      expect(para(admin).catalogo.size).to be > 400
      expect(para(admin).catalogo).to include('POST crm/pipelines', 'POST labels', 'PATCH inboxes/:id')
    end

    # Decisão do Rodrigo em 20/09/2026: o administrador pede tudo que ele mesmo
    # pode fazer na conta dele. Não há área bloqueada — o que protege é ele ler o
    # pedido literal e confirmar, e a plataforma aplicar a permissão real.
    it 'não esconde área nenhuma do administrador' do
      expect(para(admin).catalogo).to include('POST campaigns', 'POST webhooks', 'DELETE inboxes/:id')
    end
  end

  describe 'antes de confirmar' do
    # A frase pode suavizar ou errar um valor; os valores exatos não. Os dois
    # aparecem — mas em linguagem de gente, não em rota HTTP.
    it 'mostra os valores que vão mudar, sem rota nem jargão', :aggregate_failures do
      texto = para(admin).descrever('POST crm/pipelines',
                                    { descricao: 'Criar o funil Comercial.', corpo: { name: 'Comercial' } })

      expect(texto[:frase]).to eq('Criar o funil Comercial.')
      expect(texto[:detalhe]).to eq("#{I18n.t(%(autonomia.guide.fields.name))}: Comercial")
    end

    # Em 20/09/2026 a tela mostrava "POST /api/v1/accounts/16/crm/pipelines" para
    # o usuário. Lixo técnico, e estrutura interna exposta à toa.
    it 'nunca mostra endpoint, verbo HTTP ou JSON para quem usa', :aggregate_failures do
      texto = para(admin).descrever('POST crm/pipelines',
                                    { descricao: 'Criar o funil Comercial.', corpo: { name: 'Comercial' } })
      tudo = texto.values.compact.join(' ')

      expect(tudo).not_to include('/api/')
      expect(tudo).not_to include('POST')
      expect(tudo).not_to include('{')
    end

    it 'avisa quando a ação não tem volta' do
      texto = para(admin).descrever('DELETE labels/:id', { caminho: { id: 7 }, descricao: 'Apagar a etiqueta 7.' })

      expect(texto[:aviso]).to eq(I18n.t('autonomia.guide.irreversible'))
    end

    it 'não inventa aviso em ação que não apaga nada' do
      expect(para(admin).descrever('POST labels', { corpo: { title: 'vip' }, descricao: 'Criar a etiqueta VIP.' })[:aviso]).to be_nil
    end

    it 'descrever não chama a plataforma' do
      expect(Net::HTTP).not_to receive(:start)

      para(admin).descrever('POST labels', { corpo: { title: 'vip' }, descricao: 'Criar a etiqueta VIP.' })
    end
  end

  describe 'o que recusa' do
    it 'recusa ação fora do catálogo, em vez de tentar adivinhar' do
      expect { para(admin).executar('POST rota_que_nao_existe', { corpo: {} }) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.unknown_action'))
    end

    it 'recusa agente comum, mesmo pedindo direto ao serviço' do
      agente, = create_crm_agent(account: conta)

      expect { para(agente).executar('POST labels', { corpo: { title: 'x' } }) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.admin_only'))
    end

    it 'recusa agente comum já na descrição, antes de qualquer confirmação' do
      agente, = create_crm_agent(account: conta)

      expect { para(agente).descrever('POST labels', { corpo: { title: 'x' }, descricao: 'Criar.' }) }
        .to raise_error(described_class::Recusada)
    end

    # Rota com `:id` vazio atingiria o registro errado, ou nenhum.
    it 'recusa quando falta o identificador da rota' do
      expect { para(admin).executar('DELETE labels/:id', { caminho: {} }) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.missing_param', campo: 'id'))
    end

    it 'não chama a plataforma quando recusa' do
      expect(Net::HTTP).not_to receive(:start)

      begin
        para(admin).executar('POST rota_que_nao_existe', {})
      rescue described_class::Recusada
        nil
      end
    end
  end

  # Estes testes NÃO dublam a camada de transporte. A execução passa pela pilha
  # real do Rails — rotas, autenticação por token, controller, Pundit — e o que
  # se verifica é o efeito no banco. Antes eles dublavam `Net::HTTP` e mediam o
  # pedido que EU montava, não o que a plataforma aceita; foi assim que dois
  # defeitos de contrato passaram verdes e quebraram em produção.
  describe 'a execução, contra a aplicação de verdade' do
    it 'cria o registro na conta de quem pediu', :aggregate_failures do
      resultado = para(admin).executar('POST labels', { corpo: { title: 'vip' } })

      expect(resultado.ok).to be(true)
      expect(conta.labels.find_by(title: 'vip')).to be_present
    end

    # O caminho é montado com o id desta conta, sempre. Valor vindo do modelo
    # entra como segmento escapado, nunca como pedaço de rota.
    it 'não alcança registro de outra conta pelo parâmetro' do
      outra_conta, outro_admin = create_account_and_user
      alheia = outra_conta.labels.create!(title: 'defora')

      para(admin).executar('DELETE labels/:id', { caminho: { id: "../../#{outra_conta.id}/labels/#{alheia.id}" } })

      expect(outra_conta.labels.find_by(id: alheia.id)).to be_present
      expect(outro_admin.account_users.first.account_id).to eq(outra_conta.id)
    end

    it 'devolve o motivo da própria plataforma quando ela recusa', :aggregate_failures do
      conta.labels.create!(title: 'repetida')

      resultado = para(admin).executar('POST labels', { corpo: { title: 'repetida' } })

      expect(resultado.ok).to be(false)
      expect(resultado.mensagem).to be_present
    end

    # Se a plataforma nega para a pessoa, nega para o Guia: a permissão é a dela,
    # não uma cópia minha. Aqui o registro é de outra conta, e quem aplica a
    # negativa é o controller real.
    it 'respeita a negativa da plataforma em registro de outra conta' do
      outra_conta, = create_account_and_user
      alheia = outra_conta.labels.create!(title: 'alheia')

      expect(para(admin).executar('DELETE labels/:id', { caminho: { id: alheia.id } }).ok).to be(false)
    end

    it 'não derruba a resposta quando a chamada interna estoura' do
      allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_raise(StandardError, 'falhou')

      expect(para(admin).executar('POST labels', { corpo: { title: 'vip' } }).ok).to be(false)
    end
  end
end
