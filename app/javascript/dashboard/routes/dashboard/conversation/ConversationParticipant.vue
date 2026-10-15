<script>
import Spinner from 'shared/components/Spinner.vue';
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useAgentsList } from 'dashboard/composables/useAgentsList';

import ThumbnailGroup from 'dashboard/components/widgets/ThumbnailGroup.vue';
import MultiselectDropdownItems from 'shared/components/ui/MultiselectDropdownItems.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CrmMeuAcessoAPI from 'dashboard/api/crmMeuAcesso';

export default {
  components: {
    Spinner,
    ThumbnailGroup,
    MultiselectDropdownItems,
    NextButton,
  },
  props: {
    conversationId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const { agentsList } = useAgentsList(false);
    return {
      agentsList,
    };
  },
  data() {
    return {
      selectedWatchers: [],
      showDropDown: false,
      caixasRestritas: [],
    };
  },
  computed: {
    ...mapGetters({
      watchersUiFlas: 'conversationWatchers/getUIFlags',
      currentUser: 'getCurrentUser',
    }),
    watchersFromStore() {
      return this.$store.getters['conversationWatchers/getByConversationId'](
        this.conversationId
      );
    },
    watchersList: {
      get() {
        return this.selectedWatchers;
      },
      set(participants) {
        this.selectedWatchers = [...participants];
        const userIds = participants.map(el => el.id);
        this.updateParticipant(userIds);
      },
    },
    conversa() {
      return this.$store.getters.getConversationById(this.conversationId);
    },
    // #1148/#1149: quem tem acesso restrito por funil nesta caixa não se
    // adiciona; outra pessoa pode adicioná-lo.
    isSelfAddBlocked() {
      return this.caixasRestritas.includes(Number(this.conversa?.inbox_id));
    },
    dropdownAgents() {
      if (!this.isSelfAddBlocked) return this.agentsList;
      return this.agentsList.filter(
        agent =>
          agent.id !== this.currentUser.id ||
          this.selectedWatchers.some(watcher => watcher.id === agent.id)
      );
    },
    isUserWatching() {
      return this.selectedWatchers.some(
        watcher => watcher.id === this.currentUser.id
      );
    },
    thumbnailList() {
      return this.selectedWatchers.slice(0, 4);
    },
    moreAgentCount() {
      const maxThumbnailCount = 4;
      return this.watchersList.length - maxThumbnailCount;
    },
    moreThumbnailsText() {
      if (this.moreAgentCount > 1) {
        return this.$t('CONVERSATION_PARTICIPANTS.REMANING_PARTICIPANTS_TEXT', {
          count: this.moreAgentCount,
        });
      }
      return this.$t('CONVERSATION_PARTICIPANTS.REMANING_PARTICIPANT_TEXT', {
        count: 1,
      });
    },
    showMoreThumbs() {
      return this.moreAgentCount > 0;
    },
    totalWatchersText() {
      if (this.selectedWatchers.length > 1) {
        return this.$t('CONVERSATION_PARTICIPANTS.TOTAL_PARTICIPANTS_TEXT', {
          count: this.selectedWatchers.length,
        });
      }
      return this.$t('CONVERSATION_PARTICIPANTS.TOTAL_PARTICIPANT_TEXT', {
        count: 1,
      });
    },
  },
  watch: {
    conversationId() {
      this.fetchParticipants();
    },
    watchersFromStore(participants = []) {
      this.selectedWatchers = [...participants];
    },
  },
  mounted() {
    this.fetchParticipants();
    this.$store.dispatch('agents/get');
    this.fetchCaixasRestritas();
  },
  methods: {
    fetchParticipants() {
      const conversationId = this.conversationId;
      this.$store.dispatch('conversationWatchers/show', { conversationId });
    },
    async updateParticipant(userIds) {
      const conversationId = this.conversationId;
      let alertMessage = this.$t(
        'CONVERSATION_PARTICIPANTS.API.SUCCESS_MESSAGE'
      );

      try {
        await this.$store.dispatch('conversationWatchers/update', {
          conversationId,
          userIds,
        });
      } catch (error) {
        alertMessage = this.mensagemDeErro(error);
      } finally {
        useAlert(alertMessage);
      }
      this.fetchParticipants();
    },
    // Acesso por funil só existe com o CRM ligado; sem ele, ninguém é restrito.
    async fetchCaixasRestritas() {
      if (window.globalConfig?.CRM_KANBAN_ENABLED !== 'true') return;
      try {
        const { data } = await CrmMeuAcessoAPI.get();
        this.caixasRestritas = data.payload.restricted_inbox_ids;
      } catch {
        // Sem a resposta, a tela fica como sempre; a API continua recusando.
      }
    },
    // O 403 de quem tenta se adicionar com acesso restrito vem em inglês da API:
    // a tela mostra o texto dela, traduzido.
    mensagemDeErro(error) {
      if (error?.status === 403)
        return this.$t('CONVERSATION_PARTICIPANTS.API.SELF_ADD_RESTRICTED');
      return (
        error?.message || this.$t('CONVERSATION_PARTICIPANTS.API.ERROR_MESSAGE')
      );
    },
    onOpenDropdown() {
      this.showDropDown = true;
    },
    onCloseDropdown() {
      this.showDropDown = false;
    },
    onClickItem(agent) {
      const isAgentSelected = this.watchersList.some(
        participant => participant.id === agent.id
      );

      if (isAgentSelected) {
        const updatedList = this.watchersList.filter(
          participant => participant.id !== agent.id
        );

        this.watchersList = [...updatedList];
      } else {
        this.watchersList = [...this.watchersList, agent];
      }
    },
    onSelfAssign() {
      this.watchersList = [...this.selectedWatchers, this.currentUser];
    },
  },
};
</script>

<template>
  <div class="relative">
    <div class="flex justify-between">
      <div class="flex justify-between w-full mb-1">
        <div>
          <p v-if="watchersList.length" class="m-0 text-sm total-watchers">
            <Spinner v-if="watchersUiFlas.isFetching" size="tiny" />
            {{ totalWatchersText }}
          </p>
          <p v-else class="m-0 text-sm text-n-slate-10">
            {{ $t('CONVERSATION_PARTICIPANTS.NO_PARTICIPANTS_TEXT') }}
          </p>
        </div>
        <NextButton
          v-tooltip.left="$t('CONVERSATION_PARTICIPANTS.ADD_PARTICIPANTS')"
          slate
          ghost
          sm
          icon="i-lucide-settings"
          class="relative -top-1"
          :title="$t('CONVERSATION_PARTICIPANTS.ADD_PARTICIPANTS')"
          @click="onOpenDropdown"
        />
      </div>
    </div>
    <div class="flex items-center justify-between">
      <ThumbnailGroup
        :more-thumbnails-text="moreThumbnailsText"
        :show-more-thumbnails-count="showMoreThumbs"
        :users-list="thumbnailList"
      />
      <p v-if="isUserWatching" class="m-0 text-sm text-n-slate-10">
        {{ $t('CONVERSATION_PARTICIPANTS.YOU_ARE_WATCHING') }}
      </p>
      <p
        v-else-if="isSelfAddBlocked"
        data-participar-restrito
        class="m-0 text-sm text-n-slate-10"
      >
        {{ $t('CONVERSATION_PARTICIPANTS.SELF_ADD_RESTRICTED_HINT') }}
      </p>
      <NextButton
        v-else
        link
        xs
        icon="i-lucide-arrow-right"
        class="!gap-1"
        :label="$t('CONVERSATION_PARTICIPANTS.WATCH_CONVERSATION')"
        @click="onSelfAssign"
      />
    </div>
    <div
      v-on-clickaway="
        () => {
          onCloseDropdown();
        }
      "
      :class="{
        'block visible': showDropDown,
        'hidden invisible': !showDropDown,
      }"
      class="border rounded-lg shadow-lg bg-n-alpha-3 absolute backdrop-blur-[100px] border-n-strong dark:border-n-strong p-2 z-[9999] box-border top-8 w-full"
    >
      <div class="flex items-center justify-between mb-1">
        <h4
          class="m-0 overflow-hidden text-sm whitespace-nowrap text-ellipsis text-n-slate-12"
        >
          {{ $t('CONVERSATION_PARTICIPANTS.ADD_PARTICIPANTS') }}
        </h4>
        <NextButton ghost slate xs icon="i-lucide-x" @click="onCloseDropdown" />
      </div>
      <MultiselectDropdownItems
        :options="dropdownAgents"
        :selected-items="selectedWatchers"
        has-thumbnail
        @select="onClickItem"
      />
    </div>
  </div>
</template>
