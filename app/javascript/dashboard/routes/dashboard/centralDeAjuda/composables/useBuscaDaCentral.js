import { ref, computed, watch, onBeforeUnmount } from 'vue';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';

const ESPERA_MS = 300;
// A busca inteligente custa uma chamada ao modelo: espera a pessoa parar de digitar um pouco mais.
const ESPERA_INTELIGENTE_MS = 450;
// Quanto a lista por palavras espera pela Melhor resposta, contado do pedido ao Jev (~0,5 s medidos).
// Passou disso, a lista aparece sozinha e uma resposta atrasada não mexe mais no que está na tela. Com a
// alternativa (#985), soma-se a espera dela (TETO_ALTERNATIVA_MS): no caso típico, ~1 s do pedido até a tela.
const TETO_INTELIGENTE_MS = 1500;
// Com menos letras não há pergunta para o modelo entender.
const MINIMO_DE_LETRAS = 3;
// Medido na avaliação do #977: abaixo disso estavam os erros do Jev. A escolha ainda sobe para o
// topo da lista, mas sem o destaque de "Melhor resposta".
const LIMIAR_DA_MELHOR_RESPOSTA = 0.35;
// Com a Melhor resposta em destaque, a busca por palavras vira "Outros resultados" (#985): poucos, para não
// competir com a resposta.
const MAXIMO_DE_OUTROS = 3;
// A alternativa vem numa segunda chamada (~0,5 s medidos): a tela espera por ela até este teto e mostra tudo
// junto. Passou disso, abre sem ela e uma resposta atrasada não entra empurrando a lista.
const TETO_ALTERNATIVA_MS = 900;

// A régua do destaque, a mesma para a Melhor resposta e para a alternativa.
const destacavel = (artigo, certeza) =>
  Boolean(artigo) &&
  typeof certeza === 'number' &&
  certeza >= LIMIAR_DA_MELHOR_RESPOSTA;

// As duas buscas da Central (#977): por palavras (reserva) e a Melhor resposta do Jev. A tela só mostra
// resultado quando as duas terminaram (ou o teto passou): nada entra depois empurrando o que a pessoa ia tocar.
export function useBuscaDaCentral() {
  const termo = ref('');
  const resultados = ref([]);
  const erro = ref(false);
  const melhor = ref(null);
  const certeza = ref(null);
  const alternativa = ref(null);
  const certezaDaAlternativa = ref(null);
  const buscando = ref(false);
  const procurandoMelhor = ref(false);
  const procurandoAlternativa = ref(false);
  // O Enter abre o artigo assim que a Melhor resposta chega: a alternativa seria uma chamada paga perdida.
  const semAlternativa = ref(false);
  const prazoEstourado = ref(false);
  let ultimaBusca = 0;
  let ultimaInteligente = 0;
  let timerPalavras = null;
  let timerInteligente = null;
  let timerTeto = null;
  let timerAlternativa = null;

  // Espaço a mais não muda a pergunta: só o texto aparado conta.
  const termoLimpo = computed(() => termo.value.trim());
  const temTermo = computed(() => termoLimpo.value.length > 0);

  const cancelarTimers = () => {
    [timerPalavras, timerInteligente, timerTeto, timerAlternativa].forEach(
      clearTimeout
    );
    timerPalavras = null;
    timerInteligente = null;
    timerTeto = null;
    timerAlternativa = null;
  };

  const buscar = async texto => {
    timerPalavras = null;
    const pedido = ultimaBusca;
    try {
      const { data } = await CentralDeAjudaAPI.buscar(texto);
      if (pedido !== ultimaBusca) return; // chegou depois de uma busca mais nova
      resultados.value = data.resultados || [];
    } catch {
      if (pedido === ultimaBusca) erro.value = true;
    } finally {
      if (pedido === ultimaBusca) buscando.value = false;
    }
  };

  // A alternativa (#985) só é pedida com a Melhor resposta em destaque (sem ela, nunca apareceria). A tela
  // espera por ela até o teto; mesma guarda do termo: resposta de uma busca antiga não aparece.
  async function buscarAlternativa(texto, exceto, pedido) {
    procurandoAlternativa.value = true;
    timerAlternativa = setTimeout(() => {
      if (pedido === ultimaInteligente) procurandoAlternativa.value = false;
    }, TETO_ALTERNATIVA_MS);
    try {
      const { data } = await CentralDeAjudaAPI.buscarInteligente(texto, exceto);
      // Atrasada (a tela já abriu sem ela) ou de outra busca: não mexe no que a pessoa está vendo.
      if (pedido !== ultimaInteligente || !procurandoAlternativa.value) return;
      alternativa.value = data?.melhor || null;
      certezaDaAlternativa.value =
        typeof data?.certeza === 'number' ? data.certeza : null;
    } catch {
      // sem alerta: a Melhor resposta e a lista continuam valendo
    } finally {
      if (pedido === ultimaInteligente) {
        clearTimeout(timerAlternativa);
        procurandoAlternativa.value = false;
      }
    }
  }

  // A inteligente é um extra: se falhar ou passar do teto, a lista por palavras basta e ninguém é avisado.
  const buscarInteligente = async texto => {
    timerInteligente = null;
    const pedido = ultimaInteligente;
    timerTeto = setTimeout(() => {
      if (pedido === ultimaInteligente) prazoEstourado.value = true;
    }, TETO_INTELIGENTE_MS);
    try {
      const { data } = await CentralDeAjudaAPI.buscarInteligente(texto);
      if (pedido !== ultimaInteligente) return;
      // Atrasada, com a lista já na tela: não mexe no que a pessoa está vendo.
      if (prazoEstourado.value && resultados.value.length) return;
      melhor.value = data?.melhor || null;
      certeza.value = typeof data?.certeza === 'number' ? data.certeza : null;
      if (destacavel(melhor.value, certeza.value) && !semAlternativa.value) {
        buscarAlternativa(texto, melhor.value.id, pedido);
      }
    } catch {
      // sem alerta: a lista por palavras continua valendo
    } finally {
      if (pedido === ultimaInteligente) {
        clearTimeout(timerTeto);
        procurandoMelhor.value = false;
      }
    }
  };

  // Cada mudança invalida as respostas em voo (a de um termo antigo nunca aparece) e já mostra "Buscando…".
  watch(termoLimpo, texto => {
    ultimaBusca += 1;
    ultimaInteligente += 1;
    cancelarTimers();
    resultados.value = [];
    erro.value = false;
    melhor.value = null;
    certeza.value = null;
    alternativa.value = null;
    certezaDaAlternativa.value = null;
    procurandoAlternativa.value = false;
    semAlternativa.value = false;
    prazoEstourado.value = false;
    buscando.value = Boolean(texto);
    procurandoMelhor.value = texto.length >= MINIMO_DE_LETRAS;
    if (!texto) return;
    timerPalavras = setTimeout(() => buscar(texto), ESPERA_MS);
    if (procurandoMelhor.value) {
      timerInteligente = setTimeout(
        () => buscarInteligente(texto),
        ESPERA_INTELIGENTE_MS
      );
    }
  });

  // Dispara agora o que ainda esperava a pessoa parar de digitar (o Enter não espera o intervalo).
  const adiantar = () => {
    if (timerPalavras) {
      clearTimeout(timerPalavras);
      buscar(termoLimpo.value);
    }
    if (timerInteligente) {
      clearTimeout(timerInteligente);
      buscarInteligente(termoLimpo.value);
    }
  };

  // Enter: não pede a alternativa e, se ela já estava a caminho, não espera por ela.
  const dispensarAlternativa = () => {
    semAlternativa.value = true;
    procurandoAlternativa.value = false;
  };

  onBeforeUnmount(cancelarTimers);

  // Sem lista para mostrar, a espera pela Melhor resposta vai até ela voltar: é quando ela mais ajuda.
  const aguardando = computed(
    () =>
      buscando.value ||
      procurandoAlternativa.value ||
      (procurandoMelhor.value &&
        (!prazoEstourado.value || !resultados.value.length))
  );

  const emDestaque = computed(() => destacavel(melhor.value, certeza.value));

  // Só existe ao lado de uma Melhor resposta em destaque, e com a mesma régua de certeza.
  const alternativaEmDestaque = computed(
    () =>
      emDestaque.value &&
      destacavel(alternativa.value, certezaDaAlternativa.value) &&
      alternativa.value.ref !== melhor.value.ref
  );

  // Cada artigo aparece uma vez só: no cartão, ou no topo da lista quando a certeza é baixa. Com a
  // busca por palavras em erro, a escolha do Jev ainda aparece sozinha.
  const lista = computed(() => {
    const base = erro.value ? [] : resultados.value;
    if (!melhor.value) return base;
    const nosCartoes = [melhor.value.ref];
    if (alternativaEmDestaque.value) nosCartoes.push(alternativa.value.ref);
    const resto = base.filter(artigo => !nosCartoes.includes(artigo.ref));
    return emDestaque.value
      ? resto.slice(0, MAXIMO_DE_OUTROS)
      : [melhor.value, ...resto];
  });

  const total = computed(
    () =>
      lista.value.length +
      (emDestaque.value ? 1 : 0) +
      (alternativaEmDestaque.value ? 1 : 0)
  );

  return {
    termo,
    temTermo,
    erro,
    melhor,
    buscando,
    procurandoAlternativa,
    aguardando,
    emDestaque,
    alternativa,
    alternativaEmDestaque,
    lista,
    total,
    adiantar,
    dispensarAlternativa,
  };
}
