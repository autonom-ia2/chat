# frozen_string_literal: true

# Base do Guia por pacote de tradução (#1802): lib/operator_guide/pacotes/<camada>/guia-produto.md, gerada pelo
# `pnpm guia:build` só onde há pacotes/<camada>/porques.md. A conta lê a da camada mais específica que existir;
# sem arquivo, ou com o interruptor desligado, nil (fica a base geral).
#
# A instrução extra (6.B) segue o mesmo critério: pacotes/<camada>/guia-instrucao.md, escrito à mão (o build não
# o gera nem o confere). Ela vai DEPOIS da instrução geral; não substitui.
module Autonomia::Guide::BaseDoPacote
  PASTA = Rails.root.join('lib/operator_guide/pacotes')
  ARQUIVO = 'guia-produto.md'
  INSTRUCAO = 'guia-instrucao.md'

  module_function

  def caminho(account, arquivo = ARQUIVO)
    ::Autonomia::Segmentos::Pacotes.camadas(account).reverse_each do |camada|
      encontrado = PASTA.join(camada, arquivo)
      return encontrado if encontrado.file?
    end
    nil
  end

  # A instrução geral e, depois dela, a da camada; sem camada, a geral sozinha.
  def instrucao_com(geral, account)
    camada = account && caminho(account, INSTRUCAO)
    camada ? "#{geral}\n\n#{File.read(camada)}" : geral
  end

  def versao_com(versao_geral)
    arquivos = [ARQUIVO, INSTRUCAO].flat_map { |nome| Dir.glob(PASTA.join('**', nome).to_s) }.sort
    return versao_geral if arquivos.empty? || !::Autonomia::Segmentos::Pacotes.enabled?

    Digest::SHA256.hexdigest([versao_geral, *arquivos.map { |arquivo| File.read(arquivo) }].join)[0, 16]
  end
end
