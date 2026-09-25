// Roteiro do vídeo de trajeto do artigo 16.02 — "Trabalhar os resultados:
// enriquecer, contato, card, CSV". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/en/prospecting.json (locale pt-BR
// deste fork, ver nota em 16.01.mjs) e em ProspectingSearchPage.vue.
//
// NUNCA roda a busca de verdade nem chama serviço de fora. A busca e os dois
// leads são criados direto no banco pelo `preparar`
// (Autonomia::Prospecting::Search/Lead), sem passar pelo SearchRunner (que
// chamaria o Google). "Enriquecer" só aparece — nunca é clicado, porque
// chama a IA/o site do lead de verdade.
//
// A checagem de WhatsApp roda sozinha ao abrir a busca
// (`verifyLeadsWhatsApp`, em prospecting/composables/useLeadWhatsApp.js, chamado
// por useSearchHistory.js) e chama um
// serviço de fora (WAHA) para qualquer lead sem
// `metadata['whatsapp_verification']['status']` já preenchido — por isso o
// preparar grava esse status pronto nos dois leads (evita a chamada, ver
// `shouldVerifyWhatsApp`/`whatsapp_payload` no backend).
//
// "Criar card" e "CSV" são seguros de clicar de verdade: o primeiro só
// grava no banco local (Autonomia::Prospecting::CrmCardConverter, sem
// chamada externa) e o segundo monta o arquivo inteiramente no navegador
// (Blob local, sem request).
//
// Os filtros do refino (quadro do ícone Filtros) só escondem leads da tela, sem
// request: o lead 2 não tem site, então "Site: Tem" o esconde e "Limpar tudo"
// o traz de volta antes de Selecionar visíveis e CSV.
//
// Trajeto: Prospecção → Buscar leads → busca do histórico → Filtros (Ordenar,
// Site, Aplicar, Limpar tudo) → Ligar/WhatsApp no card → Enriquecer (só
// mostrar, no card: com os Detalhes abertos ele fica atrás da gaveta) →
// Detalhes de um lead → Criar card → Abrir contato/Abrir card → fechar os
// Detalhes (a gaveta cobre a lista) → Selecionar visíveis → CSV.

export const id = '16.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
# O vídeo mostra o uso do dia a dia: sem o balão de apresentação do Guia (#697).
usuaria.update!(ui_settings: (usuaria.ui_settings || {}).merge('autonomia_guide_intro_seen' => true, 'autonomia_guide_opened' => true))

Autonomia::Prospecting::Config.enable_for!(conta)

setting = Autonomia::Prospecting::Setting.for_account(conta)
setting.update!(default_crm_pipeline_id: 8, default_crm_stage_id: 11)

# Zera a busca e os leads de execuções anteriores deste vídeo (idempotente).
Autonomia::Prospecting::Search.where(account: conta, query: "Clínica odontológica").each do |s|
  Autonomia::Prospecting::Lead.where(prospect_search_id: s.id).destroy_all
  s.destroy!
end

busca = Autonomia::Prospecting::Search.create!(
  account: conta, user: usuaria,
  query: "Clínica odontológica", location: "Porto Alegre, RS",
  area_type: "radius", radius: 3000,
  area_config: { "center" => { "lat" => -30.0346, "lng" => -51.2177 }, "radius" => 3000 },
  requested_limit: 20, status: "completed", provider: "mock", categories: [], metadata: {}
)

lead1 = Autonomia::Prospecting::Lead.find_or_initialize_by(account: conta, dedupe_key: "mock:sorriso-desnorteada")
lead1.assign_attributes(
  prospect_search_id: busca.id,
  name: "Clínica Sorriso Desnorteada", category: "Clínica odontológica",
  phone: "5551999990001", website: "https://www.sorrisodesnorteada.test",
  address: "Rua das Acácias, 120", city: "Porto Alegre", state: "RS", country: "BR",
  rating: 4.6, reviews_count: 128, status: "new_lead", provider: "mock",
  provider_place_id: "mockplace-sorriso-001",
  search_rank: 1, priority_position: 1, priority_score: 91.0, score: 88.0,
  score_breakdown: {}, negative_factors: [],
  metadata: { "whatsapp_verification" => { "status" => "verified", "phone" => "+5551999990001" } },
  enrichment_status: "pending", raw_payload: {}, contact_id: nil, crm_card_id: nil
)
lead1.save!

lead2 = Autonomia::Prospecting::Lead.find_or_initialize_by(account: conta, dedupe_key: "mock:boavista-desnorteada")
lead2.assign_attributes(
  prospect_search_id: busca.id,
  name: "Ortodontia Boa Vista Desnorteada", category: "Ortodontia",
  phone: "5551999990002", website: nil,
  address: "Av. Boa Vista, 450", city: "Porto Alegre", state: "RS", country: "BR",
  rating: 4.1, reviews_count: 32, status: "new_lead", provider: "mock",
  provider_place_id: "mockplace-boavista-002",
  search_rank: 2, priority_position: 2, priority_score: 70.0, score: 65.0,
  score_breakdown: {}, negative_factors: ["missing_website"],
  metadata: { "whatsapp_verification" => { "status" => "not_whatsapp" } },
  enrichment_status: "pending", raw_payload: {}, contact_id: nil, crm_card_id: nil
)
lead2.save!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Trabalhar os resultados de uma busca',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Prospecção → Buscar leads',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/autonomia/prospecting/search`,
    aguardarTexto: 'Clínica odontológica',
    zoom: 1,
    duracaoMs: 900,
  },
  {
    legenda: 'Abra uma busca do histórico',
    acao: 'mover e clicar',
    alvo: { texto: 'Clínica odontológica' },
    aguardarTextoDepois: 'Detalhes',
    zoom: 1.6,
  },
  {
    legenda: 'Clique no ícone de Filtros',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[title="Filtros"]' },
    aguardarTextoDepois: 'Ordenar',
    zoom: 1.8,
  },
  {
    legenda: 'A ordenação muda a lista na hora',
    acao: 'parar',
    alvo: { seletor: '[role="combobox"][aria-label="Ordenar"]' },
    zoom: 1.8,
    duracaoMs: 1600,
  },
  {
    legenda: 'Escolha um filtro, como Site',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Site"]' },
    valor: 'yes',
    zoom: 1.6,
  },
  {
    legenda: 'Aplicar esconde quem não passa',
    acao: 'mover e clicar',
    alvo: { texto: 'Aplicar' },
    zoom: 1.4,
  },
  {
    legenda: 'Para ver todos de novo, abra os Filtros',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[title="Filtros"]' },
    aguardarTextoDepois: 'Limpar tudo',
    zoom: 1.8,
  },
  {
    legenda: 'Limpar tudo vale na hora',
    acao: 'mover e clicar',
    alvo: { texto: 'Limpar tudo' },
    zoom: 1.6,
  },
  {
    legenda: 'Ligar e WhatsApp ficam no rodapé do card',
    acao: 'parar',
    alvo: { texto: 'Ligar' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Enriquecer busca e-mail, redes e CNPJ',
    acao: 'parar',
    alvo: { texto: 'Enriquecer' },
    zoom: 1.8,
    duracaoMs: 1600,
  },
  {
    legenda: 'Abra os Detalhes de um lead',
    acao: 'mover e clicar',
    alvo: { texto: 'Detalhes' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja reputação e fatores de atenção',
    acao: 'parar',
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Criar card',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar card' },
    aguardarTextoDepois: 'Card criado',
    zoom: 1.8,
  },
  {
    legenda: 'Vira Abrir contato e Abrir card',
    acao: 'parar',
    alvo: { texto: 'Abrir contato' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Feche os Detalhes',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[title="Fechar detalhes"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Selecionar visíveis',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecionar visíveis' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em CSV para baixar a planilha',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[title="CSV"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
