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
      expect(texto[:detalhe]).to eq('Nome: Comercial')
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
      texto = para(admin).descrever('DELETE labels/:id', { caminho: { id: 7 } })

      expect(texto[:aviso]).to include('não tem volta')
    end

    it 'não inventa aviso em ação que não apaga nada' do
      expect(para(admin).descrever('POST labels', { corpo: { title: 'VIP' } })[:aviso]).to be_nil
    end

    it 'descrever não chama a plataforma' do
      expect(Net::HTTP).not_to receive(:start)

      para(admin).descrever('POST labels', { corpo: { title: 'VIP' } })
    end
  end

  describe 'o que recusa' do
    it 'recusa ação fora do catálogo, em vez de tentar adivinhar' do
      expect { para(admin).executar('POST rota_que_nao_existe', { corpo: {} }) }
        .to raise_error(described_class::Recusada, /não faz/)
    end

    it 'recusa agente comum, mesmo pedindo direto ao serviço' do
      agente, = create_crm_agent(account: conta)

      expect { para(agente).executar('POST labels', { corpo: { title: 'x' } }) }
        .to raise_error(described_class::Recusada, /administrador/)
    end

    it 'recusa agente comum já na descrição, antes de qualquer confirmação' do
      agente, = create_crm_agent(account: conta)

      expect { para(agente).descrever('POST labels', { corpo: { title: 'x' } }) }
        .to raise_error(described_class::Recusada)
    end

    # Rota com `:id` vazio atingiria o registro errado, ou nenhum.
    it 'recusa quando falta o identificador da rota' do
      expect { para(admin).executar('DELETE labels/:id', { caminho: {} }) }
        .to raise_error(described_class::Recusada, /Faltou dizer qual id/)
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

  describe 'a execução' do
    it 'vai pela API da conta, com o token de quem pediu' do
      capturada = responder('200', '{"id":42}')

      para(admin).executar('POST crm/pipelines', { corpo: { name: 'Comercial' } })

      expect(capturada.call.path).to eq("/api/v1/accounts/#{conta.id}/crm/pipelines")
      expect(capturada.call['api_access_token']).to eq(admin.access_token.token)
      expect(capturada.call.body).to include('Comercial')
    end

    # O caminho é montado com o id desta conta, sempre. Valor vindo do modelo
    # entra como segmento escapado, nunca como pedaço de rota.
    it 'não deixa o valor do parâmetro sair da conta' do
      capturada = responder('200')

      para(admin).executar('DELETE labels/:id', { caminho: { id: '../../999/labels/1' } })

      expect(capturada.call.path).to start_with("/api/v1/accounts/#{conta.id}/labels/")
      expect(capturada.call.path).not_to include('999/labels')
    end

    it 'devolve o motivo da própria plataforma quando ela recusa' do
      responder('422', '{"message":"Nome já está em uso"}')

      resultado = para(admin).executar('POST labels', { corpo: { title: 'VIP' } })

      expect(resultado.ok).to be(false)
      expect(resultado.mensagem).to eq('Nome já está em uso')
    end

    # Se a plataforma nega para o usuário, nega para o Guia: a permissão é a
    # dele, não uma cópia minha.
    it 'respeita a negativa de permissão da plataforma' do
      responder('403', '{"error":"Você não tem permissão"}')

      expect(para(admin).executar('PATCH inboxes/:id', { caminho: { id: 1 } }).ok).to be(false)
    end

    it 'não derruba a resposta quando a plataforma cai' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect(para(admin).executar('POST labels', { corpo: { title: 'VIP' } }).ok).to be(false)
    end
  end
end
