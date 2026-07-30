<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, sameAs } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isValidPassword } from 'shared/helpers/Validators';
import FormInput from '../../../components/Form/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const DEFAULT_AUTH_API_BASE_URL = 'https://auth.api-autonomia.com';
const MIN_PASSWORD_LENGTH = 8;
const SPECIAL_CHAR_REGEX = /[!@#$%^&*()_+\-=[\]{}|'"/\\.,`<>:;?~]/;

export default {
  components: {
    FormInput,
    NextButton,
  },
  props: {
    token: { type: String, default: '' },
    clientId: { type: String, default: '' },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      credentials: {
        password: '',
        confirmPassword: '',
      },
      submitApi: {
        showLoading: false,
        hasErrored: false,
      },
      validationApi: {
        isLoading: false,
        isInvalid: false,
        reason: '',
      },
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
          isValidPassword,
          minLength: minLength(MIN_PASSWORD_LENGTH),
        },
        confirmPassword: {
          required,
          sameAsPassword: sameAs(this.credentials.password),
        },
      },
    };
  },
  computed: {
    globalConfig() {
      return window.globalConfig || {};
    },
    authApiBaseUrl() {
      return (
        window.chatwootConfig.autonomiaAuthApiBaseUrl ||
        DEFAULT_AUTH_API_BASE_URL
      ).replace(/\/$/, '');
    },
    autonomiaSsoUrl() {
      return window.chatwootConfig.autonomiaSsoUrl || '/auth/autonomia';
    },
    canSubmit() {
      return (
        !this.validationApi.isLoading &&
        !this.validationApi.isInvalid &&
        !this.v$.$invalid &&
        Boolean(this.token)
      );
    },
    validationMessage() {
      if (!this.validationApi.isInvalid) return '';
      if (this.validationApi.reason === 'expired') {
        return this.$t('ACCEPT_INVITATION.ERRORS.EXPIRED');
      }
      return this.$t('ACCEPT_INVITATION.ERRORS.INVALID_LINK');
    },
    passwordRequirements() {
      const password = this.credentials.password || '';
      return [
        {
          id: 'length',
          met: password.length >= MIN_PASSWORD_LENGTH,
          label: this.$t('ACCEPT_INVITATION.PASSWORD.REQUIREMENTS.LENGTH', {
            min: MIN_PASSWORD_LENGTH,
          }),
        },
        {
          id: 'uppercase',
          met: /[A-Z]/.test(password),
          label: this.$t('ACCEPT_INVITATION.PASSWORD.REQUIREMENTS.UPPERCASE'),
        },
        {
          id: 'lowercase',
          met: /[a-z]/.test(password),
          label: this.$t('ACCEPT_INVITATION.PASSWORD.REQUIREMENTS.LOWERCASE'),
        },
        {
          id: 'number',
          met: /[0-9]/.test(password),
          label: this.$t('ACCEPT_INVITATION.PASSWORD.REQUIREMENTS.NUMBER'),
        },
        {
          id: 'special',
          met: SPECIAL_CHAR_REGEX.test(password),
          label: this.$t('ACCEPT_INVITATION.PASSWORD.REQUIREMENTS.SPECIAL'),
        },
      ];
    },
  },
  mounted() {
    if (!this.token) {
      this.submitApi.hasErrored = true;
      this.validationApi.isInvalid = true;
      this.validationApi.reason = 'invalid';
      useAlert(this.$t('ACCEPT_INVITATION.ERRORS.INVALID_LINK'));
      return;
    }

    this.validateInvitation();
  },
  methods: {
    showAlert(message) {
      useAlert(message);
    },
    parseErrorMessage(payload) {
      if (payload?.message) return payload.message;
      if (payload?.error?.message) return payload.error.message;
      if (typeof payload?.error === 'string') return payload.error;
      if (Array.isArray(payload?.errors) && payload.errors.length) {
        return payload.errors.join(', ');
      }
      return this.$t('ACCEPT_INVITATION.ERRORS.GENERIC');
    },
    autonomiaLoginUrl() {
      const url = new URL(this.autonomiaSsoUrl, window.location.origin);
      url.searchParams.set('prompt', 'login');
      return url.toString();
    },
    postAcceptLoginUrl(payload) {
      if (!payload?.loginUrl) {
        return this.autonomiaLoginUrl();
      }

      const loginUrl = new URL(payload.loginUrl, window.location.origin);
      const isProductLoginUrl =
        loginUrl.origin === window.location.origin &&
        loginUrl.pathname.replace(/\/$/, '') === '/login';

      return isProductLoginUrl ? this.autonomiaLoginUrl() : loginUrl.toString();
    },
    async validateInvitation() {
      this.validationApi.isLoading = true;
      this.validationApi.isInvalid = false;
      this.validationApi.reason = '';

      try {
        const url = new URL(
          '/api/v1/autonomia/product-invitations/validate',
          window.location.origin
        );
        url.searchParams.set('token', this.token);
        const response = await fetch(url.toString(), {
          headers: { Accept: 'application/json' },
        });
        const payload = await response.json().catch(() => ({}));

        if (!response.ok || payload.valid === false) {
          this.validationApi.isInvalid = true;
          this.validationApi.reason = payload.reason || 'invalid';
          this.submitApi.hasErrored = true;
          this.showAlert(this.validationMessage);
        }
      } catch {
        // Falha de rede não deve bloquear um convite potencialmente válido.
      } finally {
        this.validationApi.isLoading = false;
      }
    },
    async submitForm() {
      this.v$.$touch();

      if (!this.token) {
        this.submitApi.hasErrored = true;
        this.showAlert(this.$t('ACCEPT_INVITATION.ERRORS.INVALID_LINK'));
        return;
      }

      if (this.validationApi.isInvalid) {
        this.submitApi.hasErrored = true;
        this.showAlert(this.validationMessage);
        return;
      }

      if (this.v$.credentials.confirmPassword.$invalid) {
        this.submitApi.hasErrored = true;
        this.showAlert(this.$t('ACCEPT_INVITATION.ERRORS.PASSWORD_MATCH'));
        return;
      }

      if (this.v$.credentials.password.$invalid) {
        this.submitApi.hasErrored = true;
        this.showAlert(this.$t('ACCEPT_INVITATION.ERRORS.PASSWORD_RULES'));
        return;
      }

      this.submitApi.showLoading = true;
      this.submitApi.hasErrored = false;

      try {
        const response = await fetch(
          `${this.authApiBaseUrl}/auth/product-invitations/accept`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              token: this.token,
              password: this.credentials.password,
              confirmPassword: this.credentials.confirmPassword,
            }),
          }
        );
        const payload = await response.json().catch(() => ({}));

        if (!response.ok) {
          throw new Error(this.parseErrorMessage(payload));
        }

        window.location.assign(this.postAcceptLoginUrl(payload));
      } catch (error) {
        this.submitApi.hasErrored = true;
        this.submitApi.showLoading = false;
        this.showAlert(error.message || this.parseErrorMessage());
      }
    },
  },
};
</script>

<template>
  <main
    class="flex flex-col justify-center w-full min-h-screen py-12 bg-n-brand/5 dark:bg-n-background sm:px-6 lg:px-8"
  >
    <section class="w-full max-w-lg px-6 mx-auto">
      <img
        :src="globalConfig.logo"
        :alt="globalConfig.installationName"
        class="block w-auto h-9 mx-auto dark:hidden"
      />
      <img
        v-if="globalConfig.logoDark"
        :src="globalConfig.logoDark"
        :alt="globalConfig.installationName"
        class="hidden w-auto h-9 mx-auto dark:block"
      />

      <form
        class="p-8 mt-8 bg-white shadow dark:bg-n-solid-2 sm:shadow-lg sm:rounded-lg"
        :class="{ 'animate-wiggle': submitApi.hasErrored }"
        @submit.prevent="submitForm"
      >
        <h1 class="text-2xl font-medium tracking-tight text-n-slate-12">
          {{ $t('ACCEPT_INVITATION.TITLE') }}
        </h1>
        <p class="mt-2 text-sm leading-6 text-n-slate-11">
          {{ $t('ACCEPT_INVITATION.DESCRIPTION') }}
        </p>
        <p class="mt-2 text-sm leading-6 text-n-slate-11">
          {{ $t('ACCEPT_INVITATION.EXPIRES_HINT') }}
        </p>

        <div v-if="clientId" class="mt-4 text-xs text-n-slate-10">
          {{ $t('ACCEPT_INVITATION.PRODUCT_LABEL', { clientId }) }}
        </div>

        <div
          v-if="validationApi.isInvalid"
          class="p-3 mt-5 text-sm border rounded-lg border-n-ruby-5 bg-n-ruby-2 text-n-ruby-11"
        >
          {{ validationMessage }}
        </div>

        <div class="mt-6 space-y-5">
          <FormInput
            v-model="credentials.password"
            name="password"
            type="password"
            :label="$t('ACCEPT_INVITATION.PASSWORD.LABEL')"
            :placeholder="$t('ACCEPT_INVITATION.PASSWORD.PLACEHOLDER')"
            :has-error="v$.credentials.password.$error"
            :error-message="$t('ACCEPT_INVITATION.PASSWORD.ERROR')"
            autocomplete="new-password"
            @input="v$.credentials.password.$touch"
            @blur="v$.credentials.password.$touch"
          />
          <div
            class="p-4 text-sm border rounded-lg bg-n-slate-2 border-n-weak text-n-slate-11"
          >
            <p class="mb-3 font-medium text-n-slate-12">
              {{ $t('ACCEPT_INVITATION.PASSWORD.REQUIREMENTS.TITLE') }}
            </p>
            <ul class="grid gap-2">
              <li
                v-for="requirement in passwordRequirements"
                :key="requirement.id"
                class="flex items-start gap-2"
              >
                <span
                  class="flex items-center justify-center flex-none w-4 h-4 mt-0.5 text-[10px] rounded-full border"
                  :class="
                    requirement.met
                      ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
                      : 'border-n-slate-7 bg-n-slate-3 text-n-slate-10'
                  "
                >
                  {{ requirement.met ? '✓' : '•' }}
                </span>
                <span
                  :class="
                    requirement.met ? 'text-n-slate-11' : 'text-n-slate-10'
                  "
                >
                  {{ requirement.label }}
                </span>
              </li>
            </ul>
          </div>
          <FormInput
            v-model="credentials.confirmPassword"
            name="confirm_password"
            type="password"
            :label="$t('ACCEPT_INVITATION.CONFIRM_PASSWORD.LABEL')"
            :placeholder="$t('ACCEPT_INVITATION.CONFIRM_PASSWORD.PLACEHOLDER')"
            :has-error="v$.credentials.confirmPassword.$error"
            :error-message="$t('ACCEPT_INVITATION.CONFIRM_PASSWORD.ERROR')"
            autocomplete="new-password"
            @input="v$.credentials.confirmPassword.$touch"
            @blur="v$.credentials.confirmPassword.$touch"
          />
          <NextButton
            lg
            type="submit"
            data-testid="accept_invitation_submit_button"
            class="w-full"
            :label="$t('ACCEPT_INVITATION.SUBMIT')"
            :disabled="!canSubmit || submitApi.showLoading"
            :is-loading="submitApi.showLoading"
          />
        </div>
      </form>
    </section>
  </main>
</template>
