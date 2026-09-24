// Roteiro do vídeo de trajeto do artigo 16.03 — "Listas de leads e público
// de campanha".
//
// A Prospecção está desligada na conta 9 — liga só no banco de dev, pelo
// mesmo Config que o produto usa (Autonomia::Prospecting::Config), não por
// nenhum toggle de UI. Os leads da lista nascem no `preparar`, direto no
// banco: o vídeo NUNCA roda uma busca de verdade (bateria num provedor de
// fora). O resto do vídeo é interação real — criar lista, adicionar leads,
// criar o público — tudo local, sem chamada externa (CampaignSegmentBuilder
// só cria uma Label; não dispara nada).
//
// Achado de produto (registrado na resposta final): o campo "Campanha" do
// modal de público usa um <select> nativo do navegador — a regra do
// Rodrigo (18/09) proíbe isso. O vídeo usa `selecionar` para não fingir que
// é outro tipo de campo, e deixa no valor padrão ("Criar apenas etiqueta").

export const id = '16.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_LISTA = 'Oficinas parceiras - outubro';
const NOME_PUBLICO = 'oficinas_parceiras_outubro';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
Autonomia::Prospecting::Config.enable_for!(conta)

nome_lista = ${JSON.stringify(NOME_LISTA)}

# Idempotente: apaga só a lista (e o que ela gerou) e os leads que ESTE
# roteiro cria, mantidos pelo dedupe_key com o prefixo abaixo.
lista_antiga = conta.autonomia_prospecting_lists.find_by(name: nome_lista)
if lista_antiga
  if lista_antiga.respond_to?(:campaign_segment) && lista_antiga.campaign_segment.present?
    label_id = lista_antiga.campaign_segment["label_id"] rescue nil
    Label.where(id: label_id).destroy_all if label_id
  end
  lista_antiga.destroy!
end
conta.autonomia_prospecting_leads.where("dedupe_key LIKE ?", "video1603:%").destroy_all

leads = [
  { nome: "Oficina Mecanica Boa Vista", categoria: "Oficina mecanica", telefone: "+5511982240401", pronto: true, whatsapp_ok: true },
  { nome: "Auto Center Silva", categoria: "Oficina mecanica", telefone: "+5511982240402", pronto: true, whatsapp_ok: true },
  { nome: "Concessionaria Prime Motors", categoria: "Concessionaria", telefone: "+5511982240403", pronto: false, whatsapp_ok: false },
  { nome: "Funilaria Estrela", categoria: "Funilaria", telefone: "+5511982240404", pronto: true, whatsapp_ok: false },
  { nome: "Revisao Express", categoria: "Oficina mecanica", telefone: "+5511982240405", pronto: false, whatsapp_ok: false }
]

leads.each do |l|
  conta.autonomia_prospecting_leads.create!(
    name: l[:nome],
    category: l[:categoria],
    phone: l[:telefone],
    city: "Sao Paulo",
    state: "SP",
    country: "BR",
    provider: "mock",
    dedupe_key: "video1603:#{l[:telefone]}",
    status: l[:pronto] ? :ready_for_campaign : :qualified,
    enrichment_status: "completed",
    enrichment_completed_at: 1.day.ago,
    metadata: l[:whatsapp_ok] ? { "whatsapp_verification" => { "status" => "verified", "phone" => l[:telefone] } } : {}
  )
end

puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Listas de leads e público de campanha',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/autonomia/prospecting/lists`,
    aguardarTexto: 'Nova Lista',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Nova Lista',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova Lista' },
    zoom: 1.8,
  },
  {
    legenda: 'Dê um nome à lista',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Campanha, praça ou segmento"]' },
    texto: [NOME_LISTA],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar lista',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar lista' },
    zoom: 1.6,
    aguardarTextoDepois: 'Adicionar leads',
  },
  {
    legenda: 'Clique em Adicionar leads',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar leads' },
    zoom: 1.6,
    aguardarTextoDepois: 'Selecionar visíveis',
  },
  {
    legenda: 'Marque os leads',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecionar visíveis' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Adicionar selecionados',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar selecionados' },
    zoom: 1.6,
    aguardarTextoDepois: 'Campanha',
  },
  {
    legenda: 'Clique em Campanha para criar o público',
    acao: 'mover e clicar',
    alvo: { texto: 'Campanha' },
    zoom: 1.6,
    aguardarTextoDepois: 'Criar público',
  },
  {
    legenda: 'Veja prontos e bloqueados',
    acao: 'parar',
    alvo: { texto: 'Bloqueados' },
    zoom: 1.4,
    duracaoMs: 1300,
  },
  {
    legenda: 'Dê um nome ao público',
    acao: 'digitar',
    alvo: { seletor: '#prospecting-campaign-segment-name' },
    texto: [NOME_PUBLICO],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar público',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar público' },
    zoom: 1.8,
    aguardarTextoDepois: 'Segmento criado',
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Segmento criado' },
    zoom: 1.4,
    duracaoMs: 1000,
  },
];
