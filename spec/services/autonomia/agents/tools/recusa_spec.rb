require 'rails_helper'

# O REGISTRO DE RECUSA (entrega 6): uma linha, quatro coisas, nível que a produção emite, e nada
# do cliente. Estes exemplos travam a FORMA da linha; quem dispara cada motivo está em
# `recusa_registro_spec`, e quem impede uma saída nova sem registro está em `recusa_guarda_spec`.
RSpec.describe Autonomia::Agents::Tools::Recusa do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:linhas) { [] }

  before do
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_starting_with(described_class::PREFIXO)) do |texto|
      linhas << texto
    end
  end

  def linha
    expect(linhas.size).to eq(1)
    linhas.first
  end

  it 'escreve as quatro coisas numa linha so: conversa, agente, motivo em portugues e o que faltava' do
    # Act
    described_class.registrar('faltam_dados', slug: 'cotar_seguro', conversa: 5493, agente: agent,
                                              faltando: %w[insured.document address.zipCode])

    # Assert
    expect(linha).to eq(
      "#{described_class::PREFIXO} slug=cotar_seguro conversa=5493 agente=#{agent.id} conta=#{account.id} " \
      'onde=turno motivo=faltam_dados faltando=insured.document,address.zipCode detalhe=- ' \
      "descricao=\"#{described_class::MOTIVOS['faltam_dados']}\""
    )
  end

  # `info` é o nível que a produção emite (LOG_LEVEL=info na instância, conferido em 10/09/2026).
  # Registrar em `debug` faria a entrega virar nada, em silêncio. A prova usa um logger REAL no
  # nível da produção: se a linha sair, ela passa pelo filtro que a produção aplica.
  it 'atravessa um logger configurado como a producao (nivel info)' do
    saida = StringIO.new
    como_producao = ActiveSupport::Logger.new(saida)
    como_producao.level = Logger::INFO
    allow(Rails).to receive(:logger).and_return(como_producao)

    described_class.registrar('async_desligado', slug: 'cotar_seguro', agente: agent)

    expect(saida.string).to include("#{described_class::PREFIXO} slug=cotar_seguro")
  end

  # Só id, código e NOME de campo. Um valor que entre por engano em `faltando` vira `?`, e o
  # detalhe que não tenha forma de código vira `-`: o registro não é lugar de dado do cliente.
  it 'nao deixa passar valor de cliente nem texto livre' do
    described_class.registrar('faltam_dados', slug: 'cotar_seguro', conversa: 1, agente: agent,
                                              faltando: ['Rua das Flores, 12', 'insured.document', '04297912678'],
                                              detalhe: 'corpo={"senha":"x"}')

    expect(linha).to include('faltando=?,insured.document detalhe=-')
    expect(linha).not_to include('Flores')
    expect(linha).not_to include('04297912678')
    expect(linha).not_to include('senha')
  end

  it 'sai mesmo sem conversa e sem agente, porque a ausencia deles pode ser o proprio motivo' do
    described_class.registrar('async_indisponivel_nesta_superficie', slug: 'cotar_seguro')

    expect(linha).to include('conversa=- agente=- conta=- onde=turno motivo=async_indisponivel_nesta_superficie')
  end

  # Código fora do catálogo não pode derrubar o turno — mas também não pode passar despercebido: a
  # frase diz que falta catalogar. (A guarda estática reprova o código novo antes disso.)
  it 'nao levanta com motivo fora do catalogo, e diz que ele esta fora' do
    expect { described_class.registrar('motivo_novo', slug: 'x', agente: agent) }.not_to raise_error

    expect(linha).to include("motivo=motivo_novo faltando=- detalhe=- descricao=\"#{described_class::SEM_DESCRICAO}\"")
  end

  # O nome que o modelo pediu é o diagnóstico quando a ferramenta existe (pediu `cotar_seguro` sem
  # tê-la), e é texto livre — que pode repetir o cliente — quando não existe em lugar nenhum.
  describe '.slug_conhecido' do
    it 'mantem o nome de uma ferramenta que existe no catalogo, no cadastro ou entre os especialistas' do
      Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Estoque', slug: 'consultar_estoque',
                                      endpoint_url: 'https://exemplo.test/estoque', param_schema: [])
      Autonomia::Agents::Specialist.create!(agent: agent, name: 'Auto', slug: 'auto', description: 'auto',
                                            instruction: 'Cote.')

      expect(described_class.slug_conhecido('cotar_seguro', agent)).to eq('cotar_seguro')
      expect(described_class.slug_conhecido('consultar_estoque', agent)).to eq('consultar_estoque')
      expect(described_class.slug_conhecido('consultar_auto', agent)).to eq('consultar_auto')
    end

    it 'mascara o nome que nao existe em lugar nenhum, mesmo com forma de identificador' do
      expect(described_class.slug_conhecido('cotar_seguro_cpf_04297912678', agent)).to eq('desconhecida')
      expect(described_class.slug_conhecido('cotar_seguro_cpf_04297912678', nil)).to eq('desconhecida')
    end

    # A consulta é cortesia do registro: se o banco falhar aqui, a recusa ao modelo continua saindo.
    it 'nao levanta quando a consulta ao cadastro falha' do
      allow(agent).to receive(:tools).and_raise(ActiveRecord::ConnectionTimeoutError)

      expect(described_class.slug_conhecido('consultar_estoque', agent)).to eq('desconhecida')
    end
  end

  describe '.para_modelo' do
    let(:conversation) { create(:conversation, account: account) }
    let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil) }

    it 'devolve o JSON que o modelo ja conhece, e registra a conversa da entrega' do
      output = described_class.para_modelo('tool_http_error', slug: 'consultar_estoque', delivery: delivery,
                                                              agente: agent, detalhe: '503')

      expect(output).to eq({ error: 'tool_http_error: 503' }.to_json)
      expect(linha).to include("conversa=#{conversation.id} agente=#{agent.id}")
      expect(linha).to include('motivo=tool_http_error faltando=- detalhe=503')
    end

    it 'omite o detalhe do JSON quando nao ha um' do
      expect(described_class.para_modelo('async_desligado', slug: 'cotar_seguro', agente: agent))
        .to eq({ error: 'async_desligado' }.to_json)
    end
  end
end
