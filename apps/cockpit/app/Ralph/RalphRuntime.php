<?php

namespace App\Ralph;

use RuntimeException;

final class RalphRuntime
{
    public function projectRoot(): string
    {
        $configured = (string) config('ralph.project_root');
        $root = realpath($configured);

        if ($root === false || ! is_dir($root)) {
            throw new RuntimeException('RALPH_PROJECT_ROOT inválido.');
        }

        return $root;
    }

    public function controlDir(): string
    {
        return $this->projectRoot().DIRECTORY_SEPARATOR.'.git'.DIRECTORY_SEPARATOR.'ralph-control';
    }

    public function ledgerPath(): string
    {
        return $this->controlDir().DIRECTORY_SEPARATOR.'events.jsonl';
    }

    public function feedbackPath(): string
    {
        return $this->controlDir().DIRECTORY_SEPARATOR.'feedback'.DIRECTORY_SEPARATOR.'events.jsonl';
    }

    public function workflowPath(): string
    {
        return $this->controlDir().DIRECTORY_SEPARATOR.'workflow.json';
    }

    public function knowledgeDir(): string
    {
        return $this->projectRoot().DIRECTORY_SEPARATOR.'.ralph'.DIRECTORY_SEPARATOR.'knowledge-candidates';
    }

    public function monitorBin(): ?string
    {
        $configured = config('ralph.monitor_bin');
        if (is_string($configured) && is_file($configured)) {
            return $configured;
        }

        $fallback = $this->projectRoot().DIRECTORY_SEPARATOR.'bin'.DIRECTORY_SEPARATOR.'ralph-monitor';

        return is_file($fallback) ? $fallback : null;
    }

    public function controlBin(): ?string
    {
        $configured = config('ralph.control_bin');
        if (is_string($configured) && is_file($configured)) {
            return $configured;
        }

        $fallback = $this->projectRoot().DIRECTORY_SEPARATOR.'bin'.DIRECTORY_SEPARATOR.'ralph-control';

        return is_file($fallback) ? $fallback : null;
    }
}
