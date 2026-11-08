# frozen_string_literal: true

# Variante de artigo da Central de Ajuda por pacote de tradução (#1802).
#
# A Central é um portal só, público, gravado pelo Publicador a partir de `lib/central_de_ajuda/`. A conta de um
# pacote (seguros, seguros/corretora) lê o mesmo artigo com outras palavras: `lib/central_de_ajuda_pacotes/
# <camada>/<cap>/<id>-<slug>.md` traz o cabeçalho com o `id` (e, se mudar, o `titulo`) e só as seções `## ` que
# trocam. As outras vêm do artigo base. A troca é feita na leitura (Leitura), pela conta: nada é gravado no
# portal, então o endereço público e as contas sem pacote ficam como antes.
#
# Camadas da mais geral para a mais específica: a de seguros/corretora troca por cima da de seguros. A variante
# fica sem vídeo, porque o vídeo do artigo base mostra os botões do texto geral.
module Autonomia::CentralDeAjuda::VarianteDoPacote
  PASTA = Rails.root.join('lib/central_de_ajuda_pacotes')
  SECAO = '## '
  FIM_DO_CABECALHO = "\n---\n"
  LOG_TAG = '[central_de_ajuda][variante_do_pacote]'

  Variante = Data.define(:camada, :fonte)

  module_function

  # { '10.04' => Variante } para as camadas da conta. Os arquivos vêm na imagem: monta uma vez por conjunto de
  # camadas (em dev, a cada chamada).
  def para(camadas)
    return {} if camadas.blank?
    return montar(camadas) if Rails.env.development?

    @cache ||= {}
    @cache[[PASTA.to_s, camadas]] ||= montar(camadas).freeze
  end

  def montar(camadas)
    ids = camadas.flat_map { |camada| arquivos_da(camada).keys }.uniq
    ids.index_with { |id| compor(id, camadas) }
  end

  # { '10.04' => caminho } dos arquivos de uma camada. O capítulo é a pasta de dois dígitos.
  def arquivos_da(camada)
    Dir[PASTA.join(camada, '[0-9][0-9]', '*.md').to_s].index_by { |caminho| File.basename(caminho).split('-').first }
  end

  def compor(id, camadas)
    base = caminho_do_base(id)
    texto = File.read(base)
    camada_final = nil
    camadas.each do |camada|
      arquivo = arquivos_da(camada)[id]
      next unless arquivo

      texto = sobrepor(texto, File.read(arquivo), arquivo)
      camada_final = camada
    end
    Variante.new(camada: camada_final, fonte: ::Autonomia::CentralDeAjuda::ArtigoFonte.new(base, titulos: titulos, texto: texto))
  end

  def caminho_do_base(id)
    capitulo = id.split('.').first
    caminho = Dir[::Autonomia::CentralDeAjuda::Publicador::FONTE.join(capitulo, "#{id}-*.md").to_s].first
    raise ::Autonomia::CentralDeAjuda::ArtigoFonte::FormatoInvalido, "variante #{id} sem artigo base" if caminho.nil?

    caminho
  end

  def titulos
    mapa = JSON.parse(File.read(::Autonomia::CentralDeAjuda::Publicador::MAPA))
    mapa['capitulos'].flat_map { |capitulo| capitulo['artigos'].map { |artigo| [artigo['id'], artigo['titulo']] } }.to_h
  end

  # O artigo com as seções da variante no lugar das do base, e o título dela, se tiver.
  def sobrepor(texto_base, texto_variante, caminho)
    cabecalho, corpo = separar(texto_base, caminho)
    cabecalho_da_variante, corpo_da_variante = separar(texto_variante, caminho)
    if cabecalho_da_variante['id'] != cabecalho['id']
      raise ::Autonomia::CentralDeAjuda::ArtigoFonte::FormatoInvalido, "#{caminho}: id diferente do artigo base"
    end

    novo_cabecalho = cabecalho.merge(cabecalho_da_variante.slice('titulo'))
    "#{YAML.dump(novo_cabecalho)}---\n#{trocar_secoes(corpo, corpo_da_variante, caminho)}"
  end

  def separar(texto, caminho)
    fim = texto.start_with?("---\n") ? texto.index(FIM_DO_CABECALHO, 4) : nil
    raise ::Autonomia::CentralDeAjuda::ArtigoFonte::FormatoInvalido, "#{caminho}: sem cabeçalho" if fim.nil?

    [YAML.safe_load(texto[4...fim]), texto[(fim + FIM_DO_CABECALHO.length)..]]
  end

  def trocar_secoes(corpo, corpo_da_variante, caminho)
    _antes, *trocas = secoes(corpo_da_variante)
    inicio, *originais = secoes(corpo)
    nomes = originais.map(&:first)
    trocas.map(&:first).each do |nome|
      next if nomes.include?(nome)

      raise ::Autonomia::CentralDeAjuda::ArtigoFonte::FormatoInvalido, "#{caminho}: a seção \"#{nome}\" não existe no artigo base"
    end
    novas = trocas.to_h
    ([inicio] + originais.map { |nome, linhas| [nome, novas.fetch(nome, linhas)] }).flat_map(&:last).join
  end

  # [[nil, linhas antes da 1ª seção], [nome, linhas da seção, com o título], ...]
  def secoes(corpo)
    corpo.lines.each_with_object([[nil, []]]) do |linha, lista|
      lista << [linha.delete_prefix(SECAO).strip, []] if linha.start_with?(SECAO)
      lista.last.last << linha
    end
  end
end
