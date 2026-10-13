require 'rails_helper'

# Canal `whatsapp_modelo` do redator (#1333): prompt calibrado, schema com cabeçalho/rodapé/botões e a conferência da Meta
# que descarta a opção ruim. A IA é sempre simulada aqui.
RSpec.describe Ai::Redacao::Canais::WhatsappModelo do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:permitidas) { %w[cliente.primeiro_nome minha_empresa.nome minha_empresa.site publico.data publico.valor] }
  let(:bom) { 'Oi, {{cliente.primeiro_nome}}! Seu pedido chega em {{publico.data}}. Qualquer dúvida, é só responder aqui.' }
  let(:whatsapp) { { cabecalho: nil, rodape: 'Equipe de entregas', botoes: [], nome_sugerido: 'aviso_entrega' } }

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def opcao(texto, **extra)
    { texto: texto, chaves_usadas: [], o_que_mudou: nil, categoria_prevista: 'servico', certeza_categoria: 'alta',
      motivo_categoria: 'Fala do pedido do cliente.', whatsapp: whatsapp.merge(extra) }
  end

  def responde(opcoes)
    allow(client).to receive(:create).and_return(
      text: { status: 'ok', pergunta: nil, sugestoes: [], problemas_encontrados: [], opcoes: opcoes }.to_json
    )
  end

  def escrever(**extra)
    Ai::Redacao::Escrever.call(account: account, feature: 'modelo_redacao', canal: 'whatsapp_modelo', proposito: 'criar modelo',
                               pedido: 'avisar a entrega', limites: { max_chars: 350, categoria_desejada: nil, sem_midia: true },
                               chaves: { permitidas: permitidas, obrigatorias: [] }, colunas: { 'data' => 'data' }, opcoes: 3, **extra)
  end

  it 'monta o prompt comum + o do canal e o schema com o objeto whatsapp e a chave do botão do catálogo' do
    responde([opcao(bom)])

    escrever

    expect(client).to have_received(:create) do |args|
      expect(args[:instructions].index('# Papel')).to be < args[:instructions].index('# Canal: modelo de mensagem do WhatsApp')
      schema = args[:schema][:schema]
      expect(schema.dig(:'$defs', :opcao, :required)).to include('whatsapp')
      expect(schema.dig(:'$defs', :botao, :properties, :chave, :enum)).to eq(permitidas + [nil])
      entrada = JSON.parse(args[:input])
      expect(entrada['limites']).to eq('max_chars' => 350, 'categoria_desejada' => nil, 'sem_midia' => true)
      expect(entrada['chaves']['permitidas']).to include('chave' => 'publico.data', 'rotulo' => 'data', 'tipo' => 'data',
                                                         'exemplo' => '14/10/2026')
    end
  end

  it 'devolve a opção com tipo previsto, certeza, rodapé, botões e nome' do
    botoes = [{ tipo: 'resposta_rapida', texto: 'Confirmar', chave: nil }]
    responde([opcao(bom, botoes: botoes)])

    resultado = escrever[:opcoes].first

    expect(resultado).to include(texto: bom, categoria_prevista: 'servico', certeza_categoria: 'alta',
                                 chaves_usadas: %w[cliente.primeiro_nome publico.data])
    expect(resultado[:whatsapp]).to eq(cabecalho: nil, rodape: 'Equipe de entregas', nome_sugerido: 'aviso_entrega',
                                       botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar', chave: nil }])
  end

  it 'descarta o que a Meta recusa ou que quebra a regra da casa' do
    colado = 'Oi, {{cliente.primeiro_nome}} {{publico.data}} chega seu pedido. Qualquer dúvida, responda.'
    so_virgula = 'Oi {{cliente.primeiro_nome}}, {{publico.data}} e {{publico.valor}}. Até mais.'
    ruins = [
      opcao(colado),
      opcao(so_virgula),
      opcao(bom, rodape: 'Fale com {{minha_empresa.nome}}'),
      opcao(bom, cabecalho: '{{minha_empresa.nome}}'),
      opcao(bom, nome_sugerido: 'Aviso Entrega'),
      opcao(bom, botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar', chave: nil }, { tipo: 'link', texto: 'Ver site', chave: nil }]),
      opcao(bom, botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar meu horário agora mesmo', chave: nil }]),
      opcao(bom, botoes: [{ tipo: 'resposta_rapida', texto: 'Ver', chave: 'minha_empresa.site' }]),
      opcao("Oi! #{'a' * 1030} Até."),
      opcao(bom)
    ]
    responde(ruins)

    resultado = escrever(opcoes: 3, limites: { max_chars: 2000, categoria_desejada: nil, sem_midia: true })

    expect(resultado[:opcoes].pluck(:texto)).to eq([bom])
    expect(resultado[:descartadas]).to eq(9)
  end

  # Bateria real (13/10): "mais curto" na promoção pronta tem de manter os 4 campos da base; a regra de "um campo a cada
  # 4 palavras" no código descartava tudo. Ela fica só no prompt.
  it 'no "mais curto", aceita texto curto que mantém todos os campos da base' do
    base = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, você tem {{publico.valor}} de desconto na {{minha_empresa.nome}}. ' \
           'Quer aproveitar? Veja as ofertas no botão abaixo.'
    curto = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, tem {{publico.valor}} off na {{minha_empresa.nome}}. Aproveite!'
    responde([opcao(curto)])

    resultado = escrever(base: base, pedido: { melhorias: %w[mais_curto] })

    expect(resultado[:opcoes].pluck(:texto)).to eq([curto])
  end

  it 'aceita botão de link com campo da lista e conta a chave dele' do
    responde([opcao(bom, botoes: [{ tipo: 'link', texto: 'Ver pedido', chave: 'minha_empresa.site' }])])

    expect(escrever[:opcoes].first[:chaves_usadas]).to include('minha_empresa.site')
  end
end
