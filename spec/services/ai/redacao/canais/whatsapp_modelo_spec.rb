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
    let(:permitidas) { %w[cliente.primeiro_nome publico.numero_pedido publico.codigo publico.desconto minha_empresa.nome publico.data] }

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
      novo = 'Oi, {{cliente.primeiro_nome}}! Seu pedido {{publico.numero_pedido}} chega em {{publico.data}}. Até!'
      responde([opcao(fora), opcao(novo)])

      expect(escrever(base: base, pedido: { melhorias: %w[manter_como_servico mais_curto] })[:opcoes]).to eq([])
    end
  end

  # Calibração 13/10 (PN12-A): corpo com os mesmos 4 campos da base, e o botão de link com `publico.link`. A base é só o
  # corpo, então o campo do botão não é "campo novo no mais curto" (`Canais::Base`, com OK do Agendamento).
  it 'no "mais curto", campo só do botão não conta como campo novo do corpo (PN12)' do
    base = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, você tem {{publico.desconto}} de desconto na ' \
           '{{minha_empresa.nome}}. Quer aproveitar? Veja as ofertas no botão abaixo.'
    # Corpo com os mesmos 4 campos e corte medido de 45%. (As opções reais do PN12-A caem por outros motivos: a 1ª
    # por campos colados, a 2ª por corte de 23%, abaixo dos 25%.)
    curto = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, tem {{publico.desconto}} de desconto na ' \
            '{{minha_empresa.nome}}. Veja no botão.'
    responde([opcao(curto, botoes: [{ tipo: 'link', texto: 'Ver ofertas', chave: 'publico.link' }])])

    resultado = escrever(base: base, pedido: { melhorias: %w[mais_curto] },
                         chaves: { permitidas: %w[cliente.primeiro_nome publico.data publico.desconto minha_empresa.nome publico.link],
                                   obrigatorias: [] })

    expect(resultado[:opcoes].pluck(:texto)).to eq([curto])
  end

  describe 'melhorar: link que vai do corpo para o botão (AG15, calibração r2)' do
    let(:permitidas) { %w[cliente.primeiro_nome publico.desconto publico.link minha_empresa.nome publico.data] }
    let(:base) do
      '{{cliente.primeiro_nome}}, neste sábado as massas artesanais saem com {{publico.desconto}} de desconto para quem já é ' \
        'cliente. É só acessar {{publico.link}} e garantir o seu. Bom apetite!'
    end
    let(:sem_link) { 'Oi, {{cliente.primeiro_nome}}! Neste sábado, massas com {{publico.desconto}} de desconto. Bom apetite!' }

    it 'o campo que saiu do corpo para um botão de link continua presente' do
      responde([opcao(sem_link, botoes: [{ tipo: 'link', texto: 'Pedir agora', chave: 'publico.link' }])])

      expect(escrever(base: base, pedido: { melhorias: %w[mais_curto] })[:opcoes].pluck(:texto)).to eq([sem_link])
    end

    it 'sem o botão com o campo, tirar o link do corpo continua sendo campo removido' do
      responde([opcao(sem_link, botoes: [{ tipo: 'link', texto: 'Pedir agora', chave: nil }])])

      expect(escrever(base: base, pedido: { melhorias: %w[mais_curto] })[:opcoes]).to eq([])
    end

    it 'mesmo com o link no botão, campo novo no corpo do "mais curto" continua barrado' do
      com_data = 'Oi, {{cliente.primeiro_nome}}! Até {{publico.data}}, {{publico.desconto}} nas massas. Bom apetite!'
      responde([opcao(com_data, botoes: [{ tipo: 'link', texto: 'Pedir agora', chave: 'publico.link' }])])

      expect(escrever(base: base, pedido: { melhorias: %w[mais_curto] })[:opcoes]).to eq([])
    end

    # Fase final (AG15, risco 4 do juiz): dizer quem fala é o padrão do prompt, então o remetente pode entrar no "mais curto".
    it 'no "mais curto", acrescentar o nome da empresa (quem fala) não descarta a opção' do
      com_empresa = 'Oi, {{cliente.primeiro_nome}}! A {{minha_empresa.nome}} tem {{publico.desconto}} nas massas. Bom apetite!'
      responde([opcao(com_empresa, botoes: [{ tipo: 'link', texto: 'Pedir agora', chave: 'publico.link' }]),
                opcao(com_empresa.sub('nas massas', 'nas massas sábado'))])

      resultado = escrever(base: base, pedido: { melhorias: %w[mais_curto] })

      expect(resultado[:opcoes].pluck(:texto)).to eq([com_empresa])
    end
  end

  # Calibração r2: o "mais curto" é medido no código (texto fixo, sem os campos), não pelo que a IA diz que cortou.
  describe 'melhorar: corte medido no "mais curto"' do
    let(:permitidas) { %w[cliente.primeiro_nome publico.data publico.horario minha_empresa.nome] }
    let(:dois_campos) { "Olá, {{cliente.primeiro_nome}}! #{'a' * 70} {{publico.data}}. #{'b' * 26}" }

    # Texto com dois campos e `fixo` letras fora dos campos.
    def com_fixo(fixo)
      "Olá, {{cliente.primeiro_nome}}! #{'a' * (fixo - 16)} {{publico.data}}. Tchau!"
    end

    it 'descarta abaixo de 30%; aceita a partir de 30%' do
      fixo_base = described_class.tamanho_fixo(dois_campos)
      pouco = com_fixo((fixo_base * 0.8).round)
      bastante = com_fixo((fixo_base * 0.65).round)
      responde([opcao(pouco), opcao(bastante)])

      resultado = escrever(base: dois_campos, pedido: { melhorias: %w[mais_curto] })

      expect(described_class.corte(dois_campos, pouco)).to be < 0.30
      expect(described_class.corte(dois_campos, bastante)).to be >= 0.30
      expect(resultado[:opcoes].pluck(:texto)).to eq([bastante])
    end

    it 'com 4 campos ou mais na base, aceita a partir de 25%' do
      quatro = 'Oi {{cliente.primeiro_nome}}! Aqui é do {{minha_empresa.nome}}. Seu horário está marcado para ' \
               '{{publico.data}} às {{publico.horario}}. Se não puder vir, responda aqui que a gente remarca, tá bom? Beijos!'
      opcao_27 = 'Oi, {{cliente.primeiro_nome}}! Aqui é do {{minha_empresa.nome}}. Horário: dia {{publico.data}} às ' \
                 '{{publico.horario}}. Não pode vir? Responda que a gente remarca. Beijos!'
      corte = described_class.corte(quatro, opcao_27)
      expect(corte).to be_between(0.25, 0.30)
      responde([opcao(opcao_27)])

      expect(escrever(base: quatro, pedido: { melhorias: %w[mais_curto] })[:opcoes].pluck(:texto)).to eq([opcao_27])
      expect(escrever(base: quatro, pedido: { melhorias: %w[mais_claro] })[:opcoes].pluck(:texto)).to eq([opcao_27])
    end
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
