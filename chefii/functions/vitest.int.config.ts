import { defineConfig } from 'vitest/config';

// Callable integration tests. Run inside the emulators:
//   npm run test:integration   (from functions/, needs Java and rules-tests deps)
export default defineConfig({
  test: {
    include: ['src/**/*.int.test.ts'],
    environment: 'node',
    testTimeout: 30000,
    fileParallelism: false,
    env: { CHEFII_INTEGRATION_TEST: '1', GCLOUD_PROJECT: 'demo-chefii', FIREBASE_CONFIG: JSON.stringify({ projectId: 'demo-chefii', storageBucket: 'demo-chefii.appspot.com' }) },
  },
});
