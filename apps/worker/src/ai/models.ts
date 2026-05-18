// Copyright (C) 2025 Keygraph, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License version 3
// as published by the Free Software Foundation.

/**
 * Model tier definitions and resolution.
 *
 * Three tiers mapped to capability levels:
 * - "small"  (cheaper model — summarization, structured extraction)
 * - "medium" (primary model — tool use, general analysis)
 * - "large"  (most capable — deep reasoning, complex analysis)
 *
 * Defaults to DeepSeek models. Users override via ANTHROPIC_SMALL_MODEL /
 * ANTHROPIC_MEDIUM_MODEL / ANTHROPIC_LARGE_MODEL, which works across all providers.
 */

export type ModelTier = 'small' | 'medium' | 'large';

const DEFAULT_MODELS: Readonly<Record<ModelTier, string>> = {
  small: 'deepseek-chat',
  medium: 'deepseek-v4-pro',
  large: 'deepseek-v4-pro',
};

/** Resolve a model tier to a concrete model ID. */
export function resolveModel(tier: ModelTier = 'medium'): string {
  switch (tier) {
    case 'small':
      return process.env.ANTHROPIC_SMALL_MODEL || DEFAULT_MODELS.small;
    case 'large':
      return process.env.ANTHROPIC_LARGE_MODEL || DEFAULT_MODELS.large;
    default:
      return process.env.ANTHROPIC_MEDIUM_MODEL || DEFAULT_MODELS.medium;
  }
}

/** DeepSeek models do not support Claude's adaptive thinking feature. */
export function supportsAdaptiveThinking(_model: string): boolean {
  return false;
}
