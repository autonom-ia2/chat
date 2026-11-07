import { computed, onBeforeUnmount, ref } from 'vue';
import { useLeadLiveUpdates } from '../../composables/useLeadLiveUpdates';
import { CHANCES } from '../utils/acharChance';
import { empresaDoLead } from '../utils/acharLead';
import { temNoNome } from '../utils/acharConfiraEstados';

// #2692 — a lista da busca (v4, T1): os grupos por chance, quem fica de fora, os
// cortes leves ("Só com WhatsApp", nome) e a seleção "Vai / Não vai". A seleção
// é escolha deste envio, não estado da empresa: fica no navegador por busca
// (molde CampaignJourney/campaignDraft.js), e a demonstração não guarda.
// Ao vivo: com a API, o evento prospecting.lead.updated troca a empresa; na
// demonstração, os donos e o WhatsApp chegam um por vez num relógio.
const PASSO_AO_VIVO = 700;

export const useListaDaBusca = ({
  chaveDaSelecao,
  guardaSelecao,
  destacarPrimeiro = () => true,
}) => {
  const empresas = ref([]);
  const finais = ref(null);
  const naoVai = ref(new Set());
  const soWhatsapp = ref(false);
  const procuraNome = ref('');
  let relogio = null;

  const elegiveis = computed(() =>
    empresas.value
      .filter(empresa => !empresa.fora)
      .sort((a, b) => (b.prioridade ?? 0) - (a.prioridade ?? 0))
  );
  const visiveis = computed(() =>
    elegiveis.value.filter(
      empresa =>
        (!soWhatsapp.value || empresa.whatsapp === 'tem') &&
        temNoNome(empresa.nome, procuraNome.value)
    )
  );
  // "Chame primeiro" (rodada 2): o 1º da lista, se tem boa chance, sai do
  // grupo e ganha destaque próprio acima dos grupos; não conta em "Boa chance".
  // Quem só vê não tem essa ação: para ele, o 1º fica em "Boa chance".
  const primeiro = computed(() => {
    const topo = visiveis.value[0];
    return destacarPrimeiro() && topo?.chance === 'boa' ? topo : null;
  });
  const primeiroId = computed(() => primeiro.value?.id ?? null);
  const grupos = computed(() =>
    CHANCES.map(chave => ({
      chave,
      empresas: visiveis.value.filter(
        empresa => empresa.chance === chave && empresa.id !== primeiroId.value
      ),
    })).filter(grupo => grupo.empresas.length)
  );
  const deFora = computed(() => empresas.value.filter(empresa => empresa.fora));
  // A mandada pela gaveta já está no funil: sai das que vão (rodada 4).
  const escolhidas = computed(() =>
    elegiveis.value.filter(
      empresa => !naoVai.value.has(empresa.id) && !empresa.mandada
    )
  );
  const comWhatsapp = computed(
    () => empresas.value.filter(empresa => empresa.whatsapp === 'tem').length
  );
  const conferindoWhatsapp = computed(() =>
    empresas.value.some(empresa => empresa.whatsapp === 'conferindo')
  );
  // A barra conta todas as achadas: as que ficam de fora já vêm resolvidas,
  // então "de {total}" é o mesmo número de "{achadas} achadas".
  // Rodada 3: uma barra só para o dono e o WhatsApp ("Conferindo as empresas").
  const progresso = computed(() => {
    const procurando = empresas.value.filter(
      empresa =>
        empresa.dono.estado === 'procurando' ||
        empresa.whatsapp === 'conferindo'
    ).length;
    if (!procurando) return null;
    return {
      feitos: empresas.value.length - procurando,
      total: empresas.value.length,
    };
  });

  const lerSelecao = () => {
    try {
      return JSON.parse(window.localStorage.getItem(chaveDaSelecao()) || '[]');
    } catch {
      return [];
    }
  };
  const mudarSelecao = novo => {
    naoVai.value = novo;
    if (!guardaSelecao()) return;
    try {
      window.localStorage.setItem(chaveDaSelecao(), JSON.stringify([...novo]));
    } catch {
      // sem navegador para guardar: a seleção vale só nesta visita.
    }
  };
  const alternar = empresa => {
    const novo = new Set(naoVai.value);
    if (novo.has(empresa.id)) novo.delete(empresa.id);
    else novo.add(empresa.id);
    mudarSelecao(novo);
  };
  // "Tirar estas" do grupo "Pouca chance"; devolve como desfazer.
  const tirarPouca = () => {
    const antes = new Set(naoVai.value);
    const pouca = visiveis.value.filter(empresa => empresa.chance === 'pouca');
    mudarSelecao(new Set([...antes, ...pouca.map(empresa => empresa.id)]));
    return { n: pouca.length, desfazer: () => mudarSelecao(antes) };
  };

  const pararRelogio = () => {
    if (relogio) clearInterval(relogio);
    relogio = null;
  };
  const resolverProximo = () => {
    const indice = empresas.value.findIndex(
      empresa => !empresa.fora && empresa.dono.estado === 'procurando'
    );
    if (indice < 0 || !finais.value) {
      pararRelogio();
      return;
    }
    const final = finais.value.find(
      item => item.id === empresas.value[indice].id
    );
    empresas.value = empresas.value.map((empresa, posicao) =>
      posicao === indice ? final : empresa
    );
  };

  const aplicar = ({ dados, todasFora = false, soComWhatsapp = false }) => {
    pararRelogio();
    empresas.value = dados.empresas;
    finais.value = dados.final || null;
    let tiradas = guardaSelecao() ? lerSelecao() : dados.tiradas || [];
    if (todasFora) tiradas = dados.empresas.map(empresa => empresa.id);
    naoVai.value = new Set(tiradas);
    soWhatsapp.value = soComWhatsapp;
    procuraNome.value = '';
    if (finais.value) relogio = setInterval(resolverProximo, PASSO_AO_VIVO);
  };

  const trocar = (id, mudar) => {
    empresas.value = empresas.value.map(empresa =>
      empresa.id === id ? mudar(empresa) : empresa
    );
  };

  useLeadLiveUpdates(lead => {
    if (!guardaSelecao()) return;
    if (empresas.value.some(empresa => empresa.id === lead.id)) {
      trocar(lead.id, () => empresaDoLead(lead));
    }
  });
  onBeforeUnmount(pararRelogio);

  return {
    empresas,
    naoVai,
    soWhatsapp,
    procuraNome,
    elegiveis,
    visiveis,
    grupos,
    deFora,
    primeiro,
    primeiroId,
    conferindoWhatsapp,
    escolhidas,
    comWhatsapp,
    progresso,
    alternar,
    tirarPouca,
    aplicar,
    trocar,
    pararRelogio,
  };
};
