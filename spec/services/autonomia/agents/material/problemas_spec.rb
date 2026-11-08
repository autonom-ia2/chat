require 'rails_helper'

# #1426 (tema 4b) — a lista "um problema por vez" lida do que as conferências e o autoteste gravaram, com ids estáveis e
# só dados (o texto leigo é da tela). Fora da Fase 2 e na Lia: vazia.
RSpec.describe Autonomia::Agents::Material::Problemas do
  include_context 'with material do agente'

  def lista
    described_class.new(agent.reload).lista
  end

  def do_tipo(tipo)
    lista.select { |item| item['tipo'] == tipo }
  end

  it 'vazio: material que não teve texto nenhum' do
    ficha = material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
    material('quebrado.pdf', status: :failed, error: 'ingestion_error', trechos: [])

    expect(do_tipo('vazio')).to eq([{ 'id' => "vazio-#{ficha.id}", 'tipo' => 'vazio', 'fontes' => [ficha.id], 'nome' => 'ficha.pdf' }])
  end

  it 'leitura ruim e tabela sem cabeçalho: só enquanto a reprovação for a da conferência', :aggregate_failures do
    foto = material('tabela.jpg', source_type: 'foto', review_status: 'needs_resend',
                                  metadata: { 'conferencia' => { 'problema' => 'ocr', 'amostra' => [] } })
    planilha = material('bebidas.xlsx', review_status: 'needs_resend',
                                        metadata: { 'conferencia' => { 'problema' => 'sem_cabecalho', 'amostra' => ['Coca 350', '6,00'] } })
    material('relida.xlsx', review_status: 'accepted', metadata: { 'conferencia' => { 'problema' => 'sem_cabecalho' } })

    expect(do_tipo('ocr')).to eq([{ 'id' => "ocr-#{foto.id}", 'tipo' => 'ocr', 'fontes' => [foto.id], 'nome' => 'tabela.jpg',
                                    'foto' => true, 'amostra' => [] }])
    expect(do_tipo('sem_cabecalho').sole).to include('fontes' => [planilha.id], 'amostra' => ['Coca 350', '6,00'], 'foto' => false)
  end

  # #1426 (t4e): no material grande a tabela sem cabeçalho é aviso; o material segue aceito e o cartão aparece.
  it 'tabela sem cabeçalho de material grande: aparece como aviso, com o material aceito' do
    manual = material('manual.pdf', metadata: { 'conferencia' => { 'problema' => 'sem_cabecalho', 'amostra' => ['Cláusula 63'],
                                                                   'aviso' => true } })

    expect(do_tipo('sem_cabecalho').sole).to include('id' => "sem_cabecalho-#{manual.id}", 'fontes' => [manual.id],
                                                     'amostra' => ['Cláusula 63'], 'aviso' => true)
  end

  it 'tabela sem cabeçalho que reprovou o material não vem marcada como aviso' do
    material('bebidas.xlsx', review_status: 'needs_resend', metadata: { 'conferencia' => { 'problema' => 'sem_cabecalho' } })

    expect(do_tipo('sem_cabecalho').sole).not_to have_key('aviso')
  end

  it 'duplicado: fica o mais antigo; o par mantido pela pessoa não volta', :aggregate_failures do
    primeiro = material('horarios.pdf', metadata: { 'hash_do_texto' => 'abc' })
    segundo = material('horarios (1).pdf', metadata: { 'hash_do_texto' => 'abc' })
    material('outro.pdf', metadata: { 'hash_do_texto' => 'def' })

    expect(do_tipo('duplicado')).to eq([{ 'id' => "duplicado-#{primeiro.id}-#{segundo.id}", 'tipo' => 'duplicado',
                                          'fontes' => [primeiro.id, segundo.id], 'nome' => 'horarios.pdf',
                                          'outro' => 'horarios (1).pdf', 'manter' => primeiro.id, 'tirar' => segundo.id }])

    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', { 'duplicados_mantidos' => [[primeiro.id, segundo.id]] })
    expect(do_tipo('duplicado')).to be_empty
  end

  it 'contradição sem escolha, com o nome de onde está cada lado; a escolhida sai da lista' do
    site = material('site')
    pdf = material('horarios.pdf')
    opcoes = [{ 'fonte' => site.id, 'diz' => 'das 9h às 13h' }, { 'fonte' => pdf.id, 'diz' => 'das 9h às 12h' }]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', {
                                                         'contradicoes' => [
                                                           { 'id' => 'contradicao-a', 'assunto' => 'horário de sábado', 'opcoes' => opcoes,
                                                             'escolha' => nil },
                                                           { 'id' => 'contradicao-b', 'assunto' => 'preço', 'opcoes' => opcoes, 'escolha' => site.id }
                                                         ]
                                                       })

    expect(do_tipo('contradicao')).to eq([{ 'id' => 'contradicao-a', 'tipo' => 'contradicao', 'fontes' => [site.id, pdf.id],
                                            'assunto' => 'horário de sábado',
                                            'opcoes' => [{ 'valor' => site.id, 'onde' => 'site', 'diz' => 'das 9h às 13h' },
                                                         { 'valor' => pdf.id, 'onde' => 'horarios.pdf', 'diz' => 'das 9h às 12h' }] }])
  end

  it 'páginas de fora: o material vale; o cartão diz quantas foram lidas, do total, e por quê', :aggregate_failures do
    catalogo = material('catalogo.pdf', metadata: { 'paginas_de_fora' => { 'paginas_total' => 120, 'texto_teto' => 100,
                                                                           'texto_alem_do_teto' => 20 } })
    escaneado = material('escaneado.pdf', metadata: { 'paginas_de_fora' => { 'paginas_total' => 40, 'ocr_teto' => 30,
                                                                             'ocr_alem_do_teto' => 10, 'ocr_grandes' => [3],
                                                                             'ocr_prazo' => [], 'ocr_falhou' => [7, 8] } })
    antigo = material('antigo.pdf', metadata: { 'paginas_de_fora' => { 'ocr_prazo' => [12] } })

    expect(do_tipo('paginas_de_fora')).to eq([
                                               { 'id' => "paginas-#{catalogo.id}", 'tipo' => 'paginas_de_fora', 'fontes' => [catalogo.id],
                                                 'nome' => 'catalogo.pdf', 'motivos' => ['limite'], 'total' => 120, 'lidas' => 100 },
                                               { 'id' => "paginas-#{escaneado.id}", 'tipo' => 'paginas_de_fora', 'fontes' => [escaneado.id],
                                                 'nome' => 'escaneado.pdf', 'motivos' => %w[limite grande falha], 'total' => 40, 'lidas' => 27 },
                                               { 'id' => "paginas-#{antigo.id}", 'tipo' => 'paginas_de_fora', 'fontes' => [antigo.id],
                                                 'nome' => 'antigo.pdf', 'motivos' => ['tempo'] }
                                             ])
  end

  it 'autoteste: resposta errada e resposta inventada viram cartão; certa e confirmada não', :aggregate_failures do
    cardapio = material('cardapio.pdf')
    itens = [
      { 'pergunta' => 'Entregam no Centro?', 'origem' => 'material', 'esperado' => 'Sim, no Centro.', 'fonte' => cardapio.id,
        'resposta' => 'Não entregamos.', 'equipe' => false, 'veredito' => 'errado' },
      { 'pergunta' => 'Vende bolo?', 'origem' => 'fora', 'resposta' => 'Sim, R$ 90.', 'equipe' => false, 'veredito' => 'inventou' },
      { 'pergunta' => 'Abre domingo?', 'origem' => 'material', 'veredito' => 'certo' },
      { 'pergunta' => 'Aceita Pix?', 'origem' => 'material', 'veredito' => 'errado', 'confirmada' => true }
    ]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       { 'rodada' => 'r1', 'rodada_dos_itens' => 'r1', 'estado' => 'pronto', 'itens' => itens })

    expect(do_tipo('autoteste')).to eq([{ 'id' => 'autoteste-r1-0', 'tipo' => 'autoteste', 'fontes' => [],
                                          'pergunta' => 'Entregam no Centro?', 'resposta' => 'Não entregamos.', 'equipe' => false,
                                          'esperado' => 'Sim, no Centro.', 'onde' => 'cardapio.pdf' }])
    expect(do_tipo('autoteste_fora')).to eq([{ 'id' => 'autoteste-r1-1', 'tipo' => 'autoteste_fora', 'fontes' => [],
                                               'pergunta' => 'Vende bolo?', 'resposta' => 'Sim, R$ 90.', 'equipe' => false }])
  end

  # #1426 (t4d): "De onde o agente tirou" — os trechos que o autoteste guardou, com o nome do material na hora da leitura.
  it 'autoteste: o cartão leva os trechos usados; o de material que saiu da base some', :aggregate_failures do
    manual = material('manual.pdf')
    itens = [
      { 'pergunta' => 'Tem carro reserva?', 'origem' => 'material', 'esperado' => 'Sim, 7 dias.', 'fonte' => manual.id,
        'resposta' => 'Não tem.', 'equipe' => false, 'veredito' => 'errado',
        'trechos' => [{ 'fonte' => manual.id, 'paginas' => [226, 250], 'texto' => 'Carro reserva por 7 dias.' },
                      { 'fonte' => 999_999, 'texto' => 'De um material apagado.' }] },
      { 'pergunta' => 'Vende bolo?', 'origem' => 'fora', 'resposta' => 'Sim.', 'equipe' => false, 'veredito' => 'inventou',
        'trechos' => [] }
    ]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       { 'rodada' => 'r1', 'rodada_dos_itens' => 'r1', 'estado' => 'pronto', 'itens' => itens })

    expect(do_tipo('autoteste').sole['trechos']).to eq([{ 'onde' => 'manual.pdf', 'paginas' => [226, 250],
                                                          'texto' => 'Carro reserva por 7 dias.' }])
    expect(do_tipo('autoteste_fora').sole['trechos']).to eq([])
  end

  # Todos os trechos eram de material que saiu: o agente usou o material, então a tela não pode dizer que não usou nada.
  it 'autoteste: com todos os trechos de material que saiu da base, o cartão vai sem o bloco' do
    manual = material('manual.pdf')
    item = { 'pergunta' => 'Tem carro reserva?', 'origem' => 'material', 'esperado' => 'Sim, 7 dias.', 'fonte' => manual.id,
             'resposta' => 'Não tem.', 'equipe' => false, 'veredito' => 'errado',
             'trechos' => [{ 'fonte' => 999_999, 'texto' => 'De um material apagado.' }] }
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       { 'rodada' => 'r1', 'rodada_dos_itens' => 'r1', 'estado' => 'pronto', 'itens' => [item] })

    expect(do_tipo('autoteste').sole).not_to have_key('trechos')
  end

  it 'fora da Fase 2 ou na Lia: nada', :aggregate_failures do
    material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])

    Autonomia::Agents::Fase2.desligar!(account)
    expect(lista).to eq([])

    Autonomia::Agents::Fase2.ligar!(account)
    agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
    expect(lista).to eq([])
  end
end
