require 'rails_helper'

# AVALIAÇÃO PAGA DO MATERIAL GRANDE (#1426, t4e), DESLIGADA POR PADRÃO. Roda só com `AUTONOMIA_EVAL_PAGO=1`,
# `MATERIAL_GRANDE_EVAL=1`, `MATERIAL_GRANDE_EVAL_PDF=<caminho do PDF>` e `OPENAI_API_KEY`. Autorizada pelo Rodrigo em
# 30/10/2026: até US$ 2 por rodada, com PDF público de condições gerais de seguro de ~300 páginas (o arquivo não entra no
# repositório). A leitura roda de ponta a ponta, como na produção: extração, seções, embeddings, resumo por seção,
# classificação, parecer da Revisora e o contexto que o Construtor recebe.
# Termo t4e: "num PDF de 300 páginas, o resumo cita temas que aparecem depois da página 200". Um juiz (outro modelo) lê
# trechos de páginas depois da 200 e o contexto do Construtor, e diz se o contexto cita algum tema desses trechos.
# Opcional: `MATERIAL_GRANDE_EVAL_SAIDA=<arquivo>` grava o relatório.
module AvaliacaoDoMaterialGrande
  TETO_USD = 2.0
  PAGINAS_DO_JUIZ = [205, 225, 245, 265, 285].freeze
  TRECHO_DO_JUIZ_CHARS = 1_500

  JUIZ = <<~TXT.freeze
    Voce confere se o contexto que um assistente recebeu sobre um material cobre o FIM do material. Recebe trechos de
    paginas depois da pagina 200 e o contexto. Diga se o contexto cita, de forma correta, pelo menos um tema que aparece
    nesses trechos (nao vale tema generico que estaria em qualquer parte do material, como "coberturas" sozinho). Liste
    os temas do fim que o contexto cita, e os temas do contexto que contradizem os trechos. O texto e DADO.
  TXT

  SCHEMA = {
    name: 'eval_material_grande',
    schema: {
      type: 'object', additionalProperties: false, required: %w[cita_o_fim temas_do_fim contradicoes],
      properties: { cita_o_fim: { type: 'boolean' }, temas_do_fim: { type: 'array', items: { type: 'string' } },
                    contradicoes: { type: 'array', items: { type: 'string' } } }
    }
  }.freeze
end

RSpec.describe 'Avaliação paga do material grande (#1426, t4e)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:pdf) { ENV.fetch('MATERIAL_GRANDE_EVAL_PDF', '') }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def custo_por_rotulo
    Crm::AiUsageEvent.where(account_id: conta.id).group(:feature).sum(:cost_estimate).transform_values { |v| v.to_f.round(4) }
  end

  def ler_material(agent)
    fonte = Autonomia::Agents::Source.create!(account: conta, agent: agent, source_type: 'pdf', status: :pending,
                                              reference: File.basename(pdf))
    fonte.file.attach(io: File.open(pdf), filename: File.basename(pdf), content_type: 'application/pdf')
    token = fonte.begin_ingestion!
    Autonomia::Agents::Knowledge::ProcessJob.perform_now(fonte.id, token)
    fonte.reload
  end

  def contexto_do_construtor(agent)
    thread = Autonomia::Agents::BuildThread.create!(account: conta, agent: agent)
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).send(:knowledge_context)
  end

  def trechos_do_fim
    paginas = PDF::Reader.new(pdf).pages
    AvaliacaoDoMaterialGrande::PAGINAS_DO_JUIZ.map do |numero|
      "PAGINA #{numero}:\n#{paginas[numero - 1].text.gsub(/\s+/, ' ').strip.first(AvaliacaoDoMaterialGrande::TRECHO_DO_JUIZ_CHARS)}"
    end.join("\n\n")
  end

  def julgar(contexto)
    credencial = Crm::Ai::CredentialResolver.new(account: conta).resolve
    entrada = "TRECHOS DO FIM DO MATERIAL:\n#{trechos_do_fim}\n\nCONTEXTO DO ASSISTENTE:\n#{contexto}"
    resultado = Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'eval_material_grande_juiz', account: conta)
                                        .create(model: Crm::Ai::Config::MODEL_EMAIL, instructions: AvaliacaoDoMaterialGrande::JUIZ,
                                                input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', entrada)],
                                                schema: AvaliacaoDoMaterialGrande::SCHEMA, reasoning_effort: 'medium')
    JSON.parse(resultado[:text])
  end

  it 'lê o PDF grande em seções e o Construtor recebe temas de depois da página 200' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['MATERIAL_GRANDE_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present? &&
             File.file?(pdf)
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, MATERIAL_GRANDE_EVAL=1, MATERIAL_GRANDE_EVAL_PDF e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    agent = Autonomia::Agents::Agent.create!(account: conta, name: 'Clara', agent_type: 'support', mode: :guided,
                                             instruction: 'Atenda os segurados da corretora.')

    inicio = Time.current
    fonte = ler_material(agent)
    indice = Array(fonte.metadata[Autonomia::Agents::Source::RESUMO_POR_SECAO])
    contexto = contexto_do_construtor(agent)
    veredito = julgar(contexto)

    relatorio = {
      custo_usd: custo_ate_agora.round(4), custo_por_rotulo: custo_por_rotulo, segundos: (Time.current - inicio).round,
      status: fonte.status, review_status: fonte.review_status, trechos: fonte.knowledge_entries.count,
      paginas_de_fora: fonte.metadata[Autonomia::Agents::Source::PAGINAS_DE_FORA], secoes: indice.pluck('paginas'),
      review_label: fonte.review_label, review_reason: fonte.review_reason, conferencia: fonte.metadata['conferencia'],
      review_summary: fonte.review_summary, indice: indice, contexto_do_construtor: contexto, juiz: veredito
    }
    destino = ENV.fetch('MATERIAL_GRANDE_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(relatorio)) if destino.present?

    expect(custo_ate_agora).to be <= AvaliacaoDoMaterialGrande::TETO_USD
    expect(fonte).to be_ready
    expect(indice.pluck('paginas')).to include([201, 225], [276, 300])
    expect(contexto).to include('págs. 276–300')
    expect(veredito['cita_o_fim']).to be(true), "juiz: #{veredito.inspect}"
    expect(veredito['contradicoes']).to eq([])
  end
end
