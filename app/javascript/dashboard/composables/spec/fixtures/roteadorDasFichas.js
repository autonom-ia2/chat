// #3130 — roteador de teste com as rotas reais da ficha antiga (Contatos) e da
// ficha nova (Relacionamentos). Quem confere o endereço de um link de ficha usa
// este roteador, e não uma imitação: se o caminho de uma rota mudar, o teste
// percebe. As telas são carregadas sob demanda, então nada delas é montado.
import { routes as contatos } from 'dashboard/routes/dashboard/contacts/routes';
import { routes as relacionamentos } from 'dashboard/routes/dashboard/relacionamentos/relacionamentos.routes';

const { createRouter, createMemoryHistory } =
  await vi.importActual('vue-router');

const roteador = createRouter({
  history: createMemoryHistory(),
  routes: [...contatos, ...relacionamentos],
});

export const useRoteadorDasFichas = () => roteador;
