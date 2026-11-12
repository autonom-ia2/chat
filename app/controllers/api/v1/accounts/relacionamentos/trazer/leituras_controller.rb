# "Trazer minha lista" (#2896): enviar a planilha, ler o que o sistema achou nela, responder às perguntas da conferência e
# trazer. A planilha é guardada como importação de contatos com a marca options['trazer'] e lida em segundo plano; a
# tela pergunta de novo até sair de "lendo".
class Api::V1::Accounts::Relacionamentos::Trazer::LeiturasController < Api::V1::Accounts::Relacionamentos::Trazer::BaseController
  # GET leituras/:id?pagina=
  def show
    importacao = leituras.find(params[:id])
    render json: ::Relacionamentos::Trazer::Leitura.new(importacao, pagina: params.permit(:pagina)[:pagina]).call
  end

  # POST leituras (multipart `arquivo`)
  def create
    arquivo = params.permit(:arquivo)[:arquivo]
    erro = erro_do_arquivo(arquivo)
    return recusar_com(erro) if erro

    importacao = guardar(arquivo)
    ::CampaignImports::ValidateJob.perform_later(importacao)
    render json: { id: importacao.id, situacao: 'lendo' }, status: :created
  end

  # PATCH leituras/:id/respostas  { clientes:, coluna_cliente:, telefone: }
  def respostas
    importacao = leituras.find(params[:id])
    resposta = ::Relacionamentos::Trazer::Responder.new(importacao, params.permit(:clientes, :coluna_cliente, :telefone).to_h).call
    return recusar_com(resposta.erro, resposta.motivo) if resposta.erro
    return render json: ::Relacionamentos::Trazer::Leitura.new(importacao).call unless resposta.revalida

    ::CampaignImports::ValidateJob.perform_later(importacao)
    render json: { id: importacao.id, situacao: 'lendo' }
  end

  # POST leituras/:id/trazer — confere e põe o fechamento da conferência na fila. O segundo clique responde o mesmo.
  def trazer
    importacao = marcadas.find(params[:id])
    resultado = ::Relacionamentos::Trazer::Trazer.new(importacao).call
    return recusar_com(resultado.erro) if resultado.erro

    render json: { trazidaId: importacao.id }
  end

  private

  def erro_do_arquivo(arquivo)
    return 'arquivo_obrigatorio' unless arquivo.respond_to?(:original_filename)
    return 'tipo' unless ::CampaignImports::Config.supported_formats.include?(formato(arquivo))

    'arquivo_grande' if arquivo.size > ::CampaignImports::Config.max_file_size_bytes
  end

  def formato(arquivo)
    File.extname(arquivo.original_filename.to_s).delete('.').downcase
  end

  def guardar(arquivo)
    importacao = Current.account.campaign_imports.create!(
      user: Current.user, status: :uploaded, mode: 'single_label', batch_count: 1,
      options: { default_country: 'BR', flow: CampaignImport::CONTACTS_FLOW, create_companies: true, trazer: {} },
      source_filename: arquivo.original_filename, source_content_type: arquivo.content_type, source_byte_size: arquivo.size,
      source_format: formato(arquivo)
    )
    importacao.original_file.attach(arquivo)
    importacao
  end
end
