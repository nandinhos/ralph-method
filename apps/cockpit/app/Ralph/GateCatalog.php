<?php

namespace App\Ralph;

final class GateCatalog
{
    public const KEYS = [
        'validation',
        'quality',
        'runtime_evidence',
        'technical_review',
        'curation',
    ];

    public static function label(string $key): string
    {
        return match ($key) {
            'validation' => __('cockpit.gates.validation'),
            'quality' => __('cockpit.gates.quality'),
            'runtime_evidence' => __('cockpit.gates.runtime_evidence'),
            'technical_review' => __('cockpit.gates.technical_review'),
            'curation' => __('cockpit.gates.curation'),
            default => $key,
        };
    }

    public static function normalize(?string $key): ?string
    {
        if ($key === null || $key === '') {
            return null;
        }

        $normalized = strtolower(str_replace(['-', ' '], '_', $key));

        return in_array($normalized, self::KEYS, true) ? $normalized : $normalized;
    }

    public static function visualClass(?string $status): string
    {
        return match ($status) {
            'passed' => 'is-ok',
            'failed', 'rejected' => 'is-fail',
            default => 'is-wait',
        };
    }

    public static function gateSymbol(?string $status): string
    {
        return match ($status) {
            'passed' => '✓',
            'failed', 'rejected' => '✕',
            default => '○',
        };
    }
}
