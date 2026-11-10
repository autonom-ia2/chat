# #1431 — ingere materiais numa conta e num agente novos do banco local, pela pipeline real (processor, Chunker,
# classificador e embedding), e imprime o id do agente. A IA paga é da chave gravada pelo rodar.sh.
#   script/rag_placar/ambiente.sh runner script/rag_placar/ingerir.rb <tipo> <arquivo> [<arquivo>...]
# Cada arquivo vira um material do mesmo agente (as 5 fotos da base de foto, por exemplo).
# <tipo> é o source_type do material (pdf, xlsx, docx, json, txt, md, foto) ou link. No link, a página vem do arquivo
# HTML local: o download real passa pela trava anti-SSRF, que recusa endereço local; a leitura do HTML é a do processor.
abort 'Só em teste' unless Rails.env.test?

tipo, *caminhos = ARGV
abort 'uso: ingerir.rb <tipo> <arquivo> [<arquivo>...]' if tipo.blank? || caminhos.empty?
caminhos.each { |caminho| abort "arquivo não encontrado: #{caminho}" unless File.file?(caminho) }
abort 'link: um arquivo HTML por vez' if tipo == 'link' && caminhos.size > 1

if tipo == 'link'
  pagina = File.read(caminhos.first)
  Autonomia::Agents::Knowledge::Processors::Link.prepend(Module.new { define_method(:extract) { visible_text(pagina) } })
end

# RAG_SEGMENTO=seguros/corretora (#2801): o agente nasce com a marca de base desse segmento, como na conta de seguros em
# produção, e a resposta recebe o bloco do segmento. Sem ela, o agente fica sem base (conta geral). Resolvido antes de
# criar a conta, para um nome errado não deixar registro órfão.
if (segmento = ENV['RAG_SEGMENTO'].presence)
  texto = Autonomia::Segmentos::Bloco.for_segmento(segmento) || abort("segmento sem texto: #{segmento}")
  base = { 'segmento' => segmento, 'versao' => Autonomia::Segmentos::Bloco.versao(segmento), 'texto' => texto }
end

conta = Account.create!(name: "Placar #{tipo} #{Time.current.to_i}")
Autonomia::Agents::Fase2.ligar!(conta)
# A conta da rodada nasce com as flags de RAG que estão ligadas em produção: sem elas, o placar mede um caminho que o
# cliente não usa (até 10/11/2026 a régua rodou sem a busca híbrida, e a comparação mediu o bônus por metadado, que a
# produção não usa). O corte por estrutura liga em todas as contas das 2 stacks; o material primeiro e o uso do dado do
# trecho, em todas as contas ativas depois do deploy (comentários de cada uma no config/features.yml). Ao ligar ou
# desligar uma flag de RAG ou da resposta em produção, atualize esta lista. O segmento não é flag: vem de RAG_SEGMENTO.
FLAGS_DE_PRODUCAO = [Autonomia::Agents::BuscaHibrida::FLAG, 'rag_corte_por_estrutura', 'agente_material_primeiro',
                     'agente_usa_o_trecho'].freeze
# RAG_FLAGS=<flag_em_teste>,... liga flags a mais na conta da rodada: mede o mesmo código com e sem a mudança.
flags = FLAGS_DE_PRODUCAO + ENV.fetch('RAG_FLAGS', '').split(',').map(&:strip).reject(&:empty?)
# save!: se a gravação falhar, a rodada para em vez de medir sem as flags.
conta.enable_features(*flags.uniq)
conta.save!
agente = Autonomia::Agents::Agent.create!(account: conta, name: 'Placar', agent_type: 'support', status: :active,
                                          human_card: "Agente da régua do RAG (#{tipo}).")
agente.update!(config: agente.config.to_h.merge('base' => base)) if base

trechos = caminhos.sum do |caminho|
  fonte = Autonomia::Agents::Source.create!(account: conta, agent: agente, source_type: tipo,
                                            reference: tipo == 'link' ? 'https://site.exemplo/' : File.basename(caminho),
                                            status: :pending, metadata: {})
  fonte.file.attach(io: File.open(caminho, 'rb'), filename: File.basename(caminho)) unless tipo == 'link'
  token = fonte.begin_ingestion!
  gravados = Autonomia::Agents::Knowledge::Ingestor.new(source: fonte, token: token).perform
  fonte.update!(status: :ready, review_status: 'accepted', reviewed_at: Time.current, sync_token: nil)
  gravados
end

puts({ agente: agente.id, tipo: tipo, materiais: caminhos.size, trechos: trechos }.to_json)
