// #3130 — roteador de teste com as rotas reais da ficha antiga (Contatos) e da
// ficha nova (Relacionamentos). Quem confere o endereço de um link de ficha usa
// este roteador, e não uma imitação: se o caminho de uma rota mudar, o teste
// percebe. As telas são carregadas sob demanda, então nada delas é montado.
//
// Use com import estático e mock síncrono:
//   vi.mock('vue-router', () => ({ useRouter: () => useRoteadorDasFichas() }))
// Não importe este arquivo dentro de um mock assíncrono do `vue-router`: as
// rotas importam o `vue-router`, que espera o próprio mock terminar, e o teste
// trava para sempre (travou a CI do #3131).
import { routes as contatos } from 'dashboard/routes/dashboard/contacts/routes';
import { routes as relacionamentos } from 'dashboard/routes/dashboard/relacionamentos/relacionamentos.routes';

const { createRouter, createMemoryHistory } =
  await vi.importActual('vue-router');

const roteador = createRouter({
  history: createMemoryHistory(),
  routes: [...contatos, ...relacionamentos],
});

export const useRoteadorDasFichas = () => roteador;
