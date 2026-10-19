# frozen_string_literal: true

# Base do Guia por pacote de tradução (#1802): lib/operator_guide/pacotes/<camada>/guia-produto.md, gerada pelo
# `pnpm guia:build` só onde há pacotes/<camada>/porques.md. A conta lê a da camada mais específica que existir;
# sem arquivo, ou com o interruptor desligado, nil (fica a base geral).
module Autonomia::Guide::BaseDoPacote
  PASTA = Rails.root.join('lib/operator_guide/pacotes')
  ARQUIVO = 'guia-produto.md'

  module_function

  def caminho(account)
    ::Autonomia::Segmentos::Pacotes.camadas(account).reverse_each do |camada|
      arquivo = PASTA.join(camada, ARQUIVO)
      return arquivo if arquivo.file?
    end
    nil
  end

  def versao_com(versao_geral)
    arquivos = Dir.glob(PASTA.join('**', ARQUIVO).to_s)
    return versao_geral if arquivos.empty?

    Digest::SHA256.hexdigest([versao_geral, *arquivos.map { |arquivo| File.read(arquivo) }].join)[0, 16]
  end
end
