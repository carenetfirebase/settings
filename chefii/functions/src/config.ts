import { defineBoolean, defineSecret, defineString } from 'firebase-functions/params';

/** Canadian region (Montréal) for data residency. */
export const REGION = 'northamerica-northeast1';

// Secrets live in Google Cloud Secret Manager, never in the app bundle.
export const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
export const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');

// Model ids have no defaults on purpose: deploy prompts for them, forcing a
// check against current provider documentation (see docs/AI_CONTRACTS.md).
export const GEMINI_MODEL = defineString('GEMINI_MODEL', { description: 'Gemini model for text and chef tasks' });
export const GEMINI_VISION_MODEL = defineString('GEMINI_VISION_MODEL', { description: 'Gemini model for receipt/fridge images' });
export const OPENAI_MODEL = defineString('OPENAI_MODEL', { description: 'OpenAI model for conversation (optional provider)' });
export const OPENAI_ENABLED = defineBoolean('OPENAI_ENABLED', { default: false, description: 'Enable the optional OpenAI provider' });

/** Daily per-user limits protect cost and abuse. */
export const DAILY_LIMITS: Record<string, number> = {
  receipt: 40,
  scan: 60,
  chef_recipes: 80,
  chat: 200,
  meal_estimate: 120,
};

export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
export const MAX_RECEIPT_PAGES = 5;
