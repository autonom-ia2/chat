require 'rails_helper'

# #1426 (tema 4b) — a escolha da pessoa num problema: contradição grava qual vale e não apaga nada; duplicado tira o
# repetido ou mantém os dois; autoteste confirma a resposta. Problema que sumiu ou escolha fora das opções: Invalido.
RSpec.describe Autonomia::Agents::Material::Resolver do
  include_context 'with material do agente'

  let!(:site) { material('site', metadata: { 'hash_do_texto' => 'abc' }) }
  let!(:pdf) { material('horarios.pdf', metadata: { 'hash_do_texto' => 'abc' }) }

  def resolver(id, escolha)
    described_class.new(agent.reload, id, escolha).resolver!
  end

  def gravar_contradicao
    opcoes = [{ 'fonte' => site.id, 'diz' => 'das 9h às 13h' }, { 'fonte' => pdf.id, 'diz' => 'das 9h às 12h' }]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', {
                                                         'contradicoes' => [{ 'id' => 'contradicao-a', 'assunto' => 'sábado',
                                                                              'opcoes' => opcoes, 'escolha' => nil }]
                                                       })
  end

  it 'contradição: grava a escolha e os dois materiais ficam', :aggregate_failures do
    gravar_contradicao

    resolver('contradicao-a', pdf.id.to_s)

    item = agent.reload.config.dig('conferencia_da_base', 'contradicoes').sole
    expect(item).to include('escolha' => pdf.id)
    expect(item['escolhida_em']).to be_present
    expect(agent.sources.where(id: [site.id, pdf.id]).count).to eq(2)
  end

  it 'contradição com escolha fora das duas opções: Invalido' do
    gravar_contradicao

    expect { resolver('contradicao-a', '999') }.to raise_error(described_class::Invalido)
  end

  # "Ficar só com X" é o Tirar da gaveta (com confirmação), não uma escolha aqui: nada é apagado por este caminho.
  it 'duplicado com "um_so": Invalido, e os dois materiais ficam' do
    expect { resolver("duplicado-#{site.id}-#{pdf.id}", 'um_so') }.to raise_error(described_class::Invalido)

    expect(agent.sources.count).to eq(2)
  end

  it 'duplicado "manter os dois": os dois ficam e o par não volta' do
    resolver("duplicado-#{site.id}-#{pdf.id}", 'os_dois')

    expect(agent.sources.count).to eq(2)
    expect(Autonomia::Agents::Material::Problemas.new(agent.reload).lista).to be_empty
  end

  it 'autoteste "a resposta está certa": o item conta como certo e sai da lista' do
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', {
                                                         'rodada' => 'r1', 'rodada_dos_itens' => 'r1', 'estado' => 'pronto',
                                                         'itens' => [{ 'pergunta' => 'Abre sábado?', 'origem' => 'material', 'veredito' => 'errado' }]
                                                       })
    resolver("duplicado-#{site.id}-#{pdf.id}", 'os_dois')

    resolver('autoteste-r1-0', 'certa')

    expect(agent.reload.config.dig('autoteste', 'itens', 0, 'confirmada')).to be(true)
    expect(Autonomia::Agents::Material::Problemas.new(agent).lista).to be_empty
  end

  it 'autoteste: com outra rodada já rodando, o cartão aberto (da rodada dos itens) ainda se resolve' do
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', {
                                                         'rodada' => 'r2', 'rodada_dos_itens' => 'r1', 'estado' => 'rodando',
                                                         'itens' => [{ 'pergunta' => 'Abre sábado?', 'origem' => 'material', 'veredito' => 'errado' }]
                                                       })
    resolver("duplicado-#{site.id}-#{pdf.id}", 'os_dois')

    resolver('autoteste-r1-0', 'certa')

    expect(agent.reload.config.dig('autoteste', 'itens', 0, 'confirmada')).to be(true)
  end

  it 'problema que não existe mais, ou sem escolha nesta tela: Invalido', :aggregate_failures do
    expect { resolver('contradicao-zzz', site.id) }.to raise_error(described_class::Invalido)

    ficha = material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
    expect { resolver("vazio-#{ficha.id}", 'qualquer') }.to raise_error(described_class::Invalido)
  end
end
