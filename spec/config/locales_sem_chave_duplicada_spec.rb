require 'rails_helper'

# CHAVE DUPLICADA NO YAML DE LOCALE É DEFEITO SILENCIOSO (#380, rodada 3). O Psych não avisa: quando o
# mesmo nível tem duas chaves iguais, a ÚLTIMA vence e a primeira some inteira. Foi o que aconteceu em
# `config/locales/en.yml` em 05ad7fe9d7 (03/09, #300): um segundo bloco top-level `autonomia:` apagou o
# primeiro, e `en.autonomia.build_thread.*`, `faq.*`, `source.*`, `image_*` — e depois `agents.*` —
# passaram a responder "Translation missing" em inglês. Nenhuma spec caiu, porque `I18n.t` sem `raise`
# devolve o marcador dos dois lados de um `eq`.
#
# Esta spec percorre os NÓS do documento (não o hash carregado, que já perdeu a duplicata) e reprova
# qualquer chave repetida no mesmo nível, em qualquer arquivo de `config/locales`. O detector é provado
# contra um YAML de amostra, para que ele mesmo não fique cego sem ninguém notar.
# rubocop:disable RSpec/DescribeClass -- é a configuração de locales, não uma classe (mesmo padrão de spec/config)
RSpec.describe 'config/locales sem chave duplicada' do
  # rubocop:enable RSpec/DescribeClass
  arquivos_de_locale = Rails.root.glob('config/locales/**/*.yml').sort

  # -> lista de "caminho.da.chave (linhas a e b)" para cada chave repetida no mesmo mapeamento.
  def chaves_duplicadas(yaml)
    duplicadas = []
    percorrer(Psych.parse_stream(yaml), [], duplicadas)
    duplicadas
  end

  def percorrer(node, caminho, duplicadas)
    case node
    when Psych::Nodes::Mapping
      percorrer_mapeamento(node, caminho, duplicadas)
    when Psych::Nodes::Sequence, Psych::Nodes::Document, Psych::Nodes::Stream
      node.children.each { |filho| percorrer(filho, caminho, duplicadas) }
    end
  end

  def percorrer_mapeamento(node, caminho, duplicadas)
    vistas = {}
    node.children.each_slice(2) do |chave, valor|
      nome = chave.respond_to?(:value) ? chave.value : chave.inspect
      linha = chave.start_line + 1
      duplicadas << "#{(caminho + [nome]).join('.')} (linhas #{vistas[nome]} e #{linha})" if vistas.key?(nome)
      vistas[nome] ||= linha
      percorrer(valor, caminho + [nome], duplicadas)
    end
  end

  it 'o detector acusa uma chave repetida no mesmo nível, e só ela' do
    amostra = <<~YAML
      en:
        autonomia:
          a: '1'
        outra:
          b: '2'
        autonomia:
          c: '3'
    YAML

    expect(chaves_duplicadas(amostra)).to eq(['en.autonomia (linhas 2 e 6)'])
    expect(chaves_duplicadas("en:\n  a: '1'\n  b:\n    a: '2'\n")).to be_empty
  end

  it 'varre todos os arquivos de locale' do
    expect(arquivos_de_locale.map { |arquivo| arquivo.relative_path_from(Rails.root).to_s })
      .to include('config/locales/en.yml', 'config/locales/pt_BR.yml')
  end

  arquivos_de_locale.each do |arquivo|
    it "#{arquivo.relative_path_from(Rails.root)} não tem chave duplicada no mesmo nível" do
      expect(chaves_duplicadas(arquivo.read)).to be_empty
    end
  end

  # As chaves que o segundo bloco `autonomia:` matou em inglês voltam a resolver — e a nova de #380 junto.
  # (Em pt_BR só as que o arquivo tem; `image_*`, `source.*` e `insurance.*` nunca foram traduzidas.)
  it 'as chaves de autonomia resolvem sem cair no marcador de tradução faltando' do
    em_ingles = %w[autonomia.build_thread.message_blank autonomia.faq.not_pending autonomia.source.invalid_kind
                   autonomia.image_required autonomia.agents.instrucao_mantida autonomia.agents.escolhas_incompletas
                   autonomia.insurance.errors.encryption_unavailable]
    em_portugues = %w[autonomia.build_thread.message_blank autonomia.faq.not_pending autonomia.agents.instrucao_mantida
                      autonomia.agents.escolhas_incompletas]

    { en: em_ingles, pt_BR: em_portugues }.each do |locale, chaves|
      chaves.each do |chave|
        expect { I18n.t(chave, locale: locale, raise: true) }.not_to raise_error, "#{locale}.#{chave}"
      end
    end
  end
end
