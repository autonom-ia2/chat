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
      opcao(bom, botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar', chave: nil }, { tipo: 'link', texto: 'Ver site', chave: nil }]),
      opcao(bom, botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar meu horário agora mesmo', chave: nil }]),
      opcao(bom, botoes: [{ tipo: 'resposta_rapida', texto: 'Ver', chave: 'minha_empresa.site' }]),
      opcao("Oi! #{'a' * 1030} Até."),
      opcao(bom)
    ]
    responde(ruins)

    resultado = escrever(opcoes: 3, limites: { max_chars: 2000, categoria_desejada: nil, sem_midia: true })

    expect(resultado[:opcoes].pluck(:texto)).to eq([bom])
    expect(resultado[:descartadas]).to eq(8)
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

  # Calibração 13/10 (AG15): o nome é cosmético. Nome fora do formato vira nome no formato; a opção não cai.
  it 'normaliza o nome sugerido em vez de descartar a opção' do
    nomes = ['desconto_m massas_sabado', 'Promoção de Sábado!', '__Aviso--Entrega__', "lembrete_#{'x' * 60}", '!!!']
    responde(nomes.map { |nome| opcao(bom, nome_sugerido: nome) })

    resultado = escrever(opcoes: 3)

    expect(resultado[:descartadas]).to eq(0)
    expect(described_class.nome_normalizado('desconto_m massas_sabado')).to eq('desconto_m_massas_sabado')
    expect(described_class.nome_normalizado('Promoção de Sábado!')).to eq('promocao_de_sabado')
    expect(described_class.nome_normalizado('__Aviso--Entrega__')).to eq('aviso_entrega')
    expect(described_class.nome_normalizado("lembrete_#{'x' * 60}").length).to eq(40)
    expect(described_class.nome_normalizado('!!!')).to eq('')
    expect(resultado[:opcoes].map { |opcao| opcao[:whatsapp][:nome_sugerido] })
      .to eq(%w[desconto_m_massas_sabado promocao_de_sabado aviso_entrega])
  end

  describe 'melhorar: tirar campo da base (AG11, calibração 13/10)' do
    let(:base) do
      '{{cliente.primeiro_nome}}, seu pedido {{publico.numero_pedido}} está a caminho! Use o cupom {{publico.codigo}} e ganhe ' \
        '{{publico.desconto}} na próxima compra.'
    end
    let(:so_servico) { 'Oi, {{cliente.primeiro_nome}}! Seu pedido {{publico.numero_pedido}} está a caminho. Qualquer dúvida, responda.' }
    let(:permitidas) { %w[cliente.primeiro_nome publico.numero_pedido publico.codigo publico.desconto minha_empresa.nome] }

    it 'em "manter como serviço" e "corrigir recusa", aceita a opção que tira o campo da oferta' do
      responde([opcao(so_servico)])

      %w[manter_como_servico corrigir_recusa].each do |melhoria|
        expect(escrever(base: base, pedido: { melhorias: [melhoria] })[:opcoes].pluck(:texto)).to eq([so_servico]), melhoria
      end
    end

    it 'em "mais curto" e "mais claro", continua descartando quem tira campo da base' do
      responde([opcao(so_servico)])

      %w[mais_curto mais_claro].each do |melhoria|
        expect(escrever(base: base, pedido: { melhorias: [melhoria] })[:opcoes]).to eq([]), melhoria
      end
    end

    it 'mesmo tirando campo, não aceita campo fora da lista nem campo novo no "mais curto"' do
      fora = 'Oi, {{cliente.primeiro_nome}}! Seu pedido {{publico.numero_pedido}} sai hoje de {{minha_empresa.endereco}}. Até!'
      novo = 'Oi, {{cliente.primeiro_nome}}! Seu pedido {{publico.numero_pedido}} da {{minha_empresa.nome}} saiu. Até!'
      responde([opcao(fora), opcao(novo)])

      expect(escrever(base: base, pedido: { melhorias: %w[manter_como_servico mais_curto] })[:opcoes]).to eq([])
    end
  end

  # Calibração 13/10 (PN12-A): corpo com os mesmos 4 campos da base, e o botão de link com `publico.link`. A base é só o
  # corpo, então o campo do botão não é "campo novo no mais curto" (`Canais::Base`, com OK do Agendamento).
  it 'no "mais curto", campo só do botão não conta como campo novo do corpo (PN12)' do
    base = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, você tem {{publico.desconto}} de desconto na ' \
           '{{minha_empresa.nome}}. Quer aproveitar? Veja as ofertas no botão abaixo.'
    # A 2ª opção real do PN12-A. A 1ª ("…{{cliente.primeiro_nome}}! {{publico.desconto}}…") cai por campos colados.
    curto = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, aproveite {{publico.desconto}} de desconto na ' \
            '{{minha_empresa.nome}}. Confira as ofertas no botão.'
    responde([opcao(curto, botoes: [{ tipo: 'link', texto: 'Ver ofertas', chave: 'publico.link' }])])

    resultado = escrever(base: base, pedido: { melhorias: %w[mais_curto] },
                         chaves: { permitidas: %w[cliente.primeiro_nome publico.data publico.desconto minha_empresa.nome publico.link],
                                   obrigatorias: [] })

    expect(resultado[:opcoes].pluck(:texto)).to eq([curto])
  end

  # Condição do Agendamento para o PN12: a chave proibida num botão continua pega (a soma corpo + botões vai para a
  # conferência das chaves), também no melhorar.
  it 'chave fora da lista num botão continua descartando a opção, inclusive no melhorar' do
    base = 'Oi, {{cliente.primeiro_nome}}! Seu pedido chega em {{publico.data}}. Qualquer dúvida, responda.'
    responde([opcao(bom, botoes: [{ tipo: 'link', texto: 'Ver pedido', chave: 'minha_empresa.endereco' }])])

    expect(escrever[:descartadas]).to eq(1)
    expect(escrever(base: base, pedido: { melhorias: %w[mais_curto] })[:descartadas]).to eq(1)
  end

  it 'aceita botão de link com campo da lista e conta a chave dele' do
    responde([opcao(bom, botoes: [{ tipo: 'link', texto: 'Ver pedido', chave: 'minha_empresa.site' }])])

    expect(escrever[:opcoes].first[:chaves_usadas]).to include('minha_empresa.site')
  end
end
